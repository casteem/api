class RenameCachedScoreColumnOnUsers < ActiveRecord::Migration[5.2]
  def change
    rename_column :users, :cached_diversity_score, :cached_user_score
    rename_column :users, :diversity_score_updated_at, :user_score_updated_at

    Post.for_a_month.each do |post|
      post.valid_votes.each do |v|
        v['weight'] = post.active_votes.select { |a| a['voter'] == v['voter'] }.first['weight']
      end
      post.save!

      puts "weight updated - #{post.id}"
    end

    User.all.each do |user|
      old_score = user.cached_user_score
      user.user_score(true, false)

      puts "@#{user.username}: #{old_score.round(2)} -> #{user.user_score.round(2)}"
    end
  end
end
