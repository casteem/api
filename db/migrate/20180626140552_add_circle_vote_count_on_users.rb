class AddCircleVoteCountOnUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :circle_vote_count, :integer, default: 0
  end
end
