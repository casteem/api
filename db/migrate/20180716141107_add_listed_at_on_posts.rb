class AddListedAtOnPosts < ActiveRecord::Migration[5.2]
  def change
    add_column :posts, :listed_at, :datetime, default: nil
    add_index :posts, :listed_at
    Post.all.update_all('listed_at = created_at')
  end
end
