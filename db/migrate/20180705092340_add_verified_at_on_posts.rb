class AddVerifiedAtOnPosts < ActiveRecord::Migration[5.2]
  def change
    add_column :posts, :verified_at, :datetime, default: nil
    add_index :posts, :verified_at

    Post.verified.update_all('verified_at = created_at')
  end
end
