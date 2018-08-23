class AddIndexOnPostsTitle < ActiveRecord::Migration[5.2]
  def up
    execute "CREATE INDEX index_posts_on_lowercase_title ON posts USING btree (lower(title));"
  end

  def down
    execute "DROP INDEX index_posts_on_lowercase_title;"
  end
end
