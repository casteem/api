class AddVotingSessionOnPosts < ActiveRecord::Migration[5.2]
  def change
    add_column :posts, :session_date, :date, default: nil
    add_column :posts, :session_number, :integer, default: nil
    add_index :posts, [:session_date, :session_number]
    remove_index :posts, :created_at

    Post.where('created_at < ?', Time.zone.today.to_time).update_all('session_date = DATE(created_at), session_number = 0')
  end
end
