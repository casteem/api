class PostsController < ApplicationController
  before_action :ensure_login!, only: [:create, :update, :moderate, :set_moderator, :destroy, :exists]
  before_action :set_post, only: [:show, :update, :refresh, :moderate, :set_moderator, :destroy]
  before_action :check_ownership!, only: [:update, :destroy]
  before_action :check_moderator!, only: [:moderate, :set_moderator]
  before_action :set_sort_option, only: [:index, :author, :top, :tag]

  # GET /posts
  def index
    days_ago = params[:days_ago].to_i
    days_ago = 365 if days_ago > 365
    days_ago = 0 if days_ago < -1 # -1 for Most Recent

    today = Time.zone.today.to_time

    @posts = if days_ago > 0
      Post.where('listed_at >= ? AND listed_at < ?', today - days_ago.days, today - (days_ago - 1).days)
    else # Today
      Post.where('listed_at >= ?', today)
    end

    @posts = if days_ago == -1
      @posts.where(is_active: true, is_verified: true).order(created_at: :desc).limit(20).sample(3)
    elsif params[:sort] == 'unverified'
      @posts.where(is_verified: false).order(created_at: :asc)
    else
      @posts.where(is_active: true).order(@sort)
    end

    render json: @posts.as_json(except: [:active_votes])
  end

  def top
    now = Time.zone.now

    @posts = case params[:period]
      when 'week'
        Post.where('listed_at >= ?', now.beginning_of_week)
      when 'month'
        Post.where('listed_at >= ?', now.beginning_of_month)
      else
        Post.all
      end.where(is_active: true).order(@sort)

    render_pages
  end


  def search
    # TODO: Split the serach flow between
    #   1. title
    #   2. url
    # so the query can be more efficient

    raw_query = params[:q].to_s.gsub(/[^A-Za-z0-9:\-\/\.]/, ' ')
    query = raw_query.gsub(/[^A-Za-z0-9\.\s]/, ' ').first(40)

    render json: { posts: [] } and return if query.blank?

    terms = query.split
    no_space = query.gsub(/[\s\t]/, '')

    @posts = Post.from("""
      (SELECT *,
        to_tsvector('english', author) ||
        to_tsvector('english', title) ||
        to_tsvector('english', tagline) ||
        to_tsvector('english', immutable_array_to_string(tags, ' ')) as document
      FROM posts) posts
    """).
      where(is_active: true).
      where("url LIKE '#{raw_query}%' OR lower(title) LIKE '#{raw_query.downcase}%' OR posts.document @@ to_tsquery('english', '#{no_space} | #{terms.join(' & ')}')").
      order({ hunt_score: :desc }).limit(50)

    render json: { posts: @posts.as_json(except: [:document]) }
  end

  # GET /posts/@:author
  def author
    @posts = Post.where(author: params[:author]).order(@sort)

    render_pages
  end

  # GET /tag/:tag
  def tag
    @posts = Post.where(":tag = ANY(tags)", tag: params[:tag]).order(@sort)

    render_pages(50)
  end

  # GET /posts/@:author/:permlink
  def show
    render json: @post
  end

  # GET /posts/exists
  def exists
    if ecommerce?(params[:url])
      render json: { result: "We don't accept e-commerce or affiliate sites. Please check our posting guidelines." } and return
    end

    result = existing_post(params[:url])
    if result == 'INVALID'
      render json: { result: 'Invalid URL. Please include http or https at the beginning.' }
    elsif result
      render json: { result: 'The product link already exists', url: result.key }
    else
      render json: { result: 'OK' }
    end
  end

  # POST /posts
  def create
    @post = Post.find_by(author: post_params[:author], permlink: post_params[:permlink])

    unless @post
      @post = Post.find_by(url: post_params[:url], author: post_params[:author])
    end

    today = Time.zone.today.to_time
    if @post
      if @post.active?
        render json: { error: 'You have already posted the same product on Steemhunt.' }, status: :unprocessable_entity and return
      else
        @post.assign_attributes(post_params)
        @post.is_active = true
        @post.is_verified = false
        @post.created_at = Time.now
        @post.listed_at = Time.now
        @post.verified_by = nil
      end
    else
      @post = Post.new(post_params)
    end

    if existing_post(@post.url) # if 'INVALID' or true
      render json: { error: 'The product already exists on Steemhunt.' }, status: :unprocessable_entity and return
    end

    if @post.save
      render json: @post, status: :created
    else
      render json: { error: @post.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  # PUT /posts/@:author/:permlink
  def update
    if @post.update(post_params)
      render json: @post
    else
      render json: { error: @post.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  # DELETE /posts/@:author/:permlink
  def destroy
    @post.update!(is_active: false, is_verified: true)

    render json: { head: :no_content }
  end

  # PATCH /posts/refresh/@:author/:permlink
  def refresh
    if @post.update(post_refresh_params)
      render json: @post.as_json(only: [:hunt_score, :valid_votes])
    else
      render json: { error: 'UNPROCESSABLE_ENTITY' }, status: :unprocessable_entity
    end
  end

  # PATCH /set_moderator/@:author/:permlink
  def set_moderator
    if @post.author == @current_user.username
      render json: { error: 'You cannot review your own content' }, status: :forbidden and return
    end

    if @post.verified_by.blank?
      @post.update!(verified_by: @current_user.username)
    end

    render_moderator_fields
  end

  # PATCH /moderate/@:author/:permlink
  def moderate
    if @post.verified_by != @current_user.username && !@current_user.admin? && !@current_user.guardian?
      render json: { error: "This product is in review by #{@post.verified_by}" }, status: :forbidden
    else
      mod_params = post_moderate_params.merge(verified_by: @current_user.username)

      # roll-over to Today's ranking when post is re-verified from hidden status
      mod_params[:listed_at] = Time.now if !@post.is_active && mod_params[:is_active]

      # unverify - unsets the moderator
      mod_params[:verified_by] = nil if mod_params[:is_active] && !mod_params[:is_verified]

      if @post.update!(mod_params)
        render_moderator_fields
      else
        render json: { error: 'UNPROCESSABLE_ENTITY' }, status: :unprocessable_entity
      end
    end
  end

  def signed_url
    uid = "#{SecureRandom.hex(4)}-#{params[:filename]}"
    path = "#{Rails.env}/steemhunt/#{Time.zone.now.strftime('%Y-%m-%d')}/#{uid}"

    s3 = Aws::S3::Resource.new
    obj = s3.bucket('huntimages').object(path)

    if obj
      render json: {
        uid: uid,
        image_url: obj.public_url,
        signed_url: obj.presigned_url(:put, acl: 'public-read')
      }
    else
      render json: { error: 'UNPROCESSABLE_ENTITY' }, status: :unprocessable_entity
    end
  end

  private
    def render_moderator_fields
      render json: @post.as_json(only: [:is_active, :is_verified, :verified_by])
    end

    def render_pages(per_page = 20)
      page = params[:page].to_i
      page = 1 if page < 1

      if page == 1
        render json: {
          total_count: @posts.count,
          total_payout: @posts.sum(:payout_value),
          posts: @posts.paginate(page: page, per_page: per_page)
        }
      else
        render json: { posts: @posts.paginate(page: page, per_page: per_page) }
      end
    end

    def set_sort_option
      @sort = case params[:sort]
        when 'created'
          { listed_at: :desc }
        when 'vote_count'
          'json_array_length(valid_votes) DESC'
        when 'comment_count'
          { children: :desc }
        when 'payout'
          { payout_value: :desc }
        when 'random'
          Arel.sql('random()')
        else
          { hunt_score: :desc, payout_value: :desc, created_at: :desc }
        end
    end

    def set_post
      @post = Post.find_by(author: params[:author], permlink: params[:permlink])
      render_404 and return unless @post
    end

    def post_params
      params.require(:post).permit(:author, :url, :title, :tagline, :description, :permlink, :is_active, tags: [],
        beneficiaries: [ :account, :weight ],
        images: [ :id, :name, :link, :width, :height, :type, :deletehash ])
    end

    def post_refresh_params
      params.require(:post).permit(:payout_value, :children, active_votes: [ :voter, :weight, :rshares, :percent, :reputation, :time ])
    end

    def post_moderate_params
      params.require(:post).permit(:is_active, :is_verified)
    end

    def search_url(uri)
      begin
        parsed = URI.parse(uri)
      rescue URI::InvalidURIError
        return nil
      end

      return nil if parsed.host.blank? || !['http', 'https'].include?(parsed.scheme)

      host = parsed.host.gsub('www.', '')
      path = parsed.path == '/' ? '' : parsed.path

      # Google Playstore apps use parameters for different products
      return "#{uri}%" if host == 'play.google.com' && path == '/store/apps/details'

      ["http%://#{host}#{path}%", "http%://www.#{host}#{path}%"] # NOTE: Cannot use index scan
    end

    def existing_post(uri)
      # Index scan first
      post = Post.where('url LIKE ?', "#{uri}%").where.not(author: @current_user.username).first
      return post unless post.nil?

      if search = search_url(uri)
        if search.is_a?(Array)
          Post.where('url LIKE ? OR url LIKE ?', search[0], search[1])
        else
          Post.where('url LIKE ?', search)
        end.where.not(author: @current_user.username).first
      else
        'INVALID'
      end
    end

    def ecommerce?(url)
      ecommerce_domains = [
        /alibaba\.com/,
        /aliexpress\.com/,
        # /amazon\.co/,
        /awesomeinventions\.com/,
        /ebay\.com/,
        /etsy\.com/,
        /flipkart\.com/,
        /groupon\.com/,
        /jd\.com/,
        /shopify\.com/,
        /rakuten\.com/,
        /thinkgeek\.com/,
        /uncommongoods\.com/,
        /trendyproductsshop\.com/
      ]
      ecommerce_domains.any? { |d| url =~ d }
    end
end
