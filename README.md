# Steemhunt Back-end

## Stacks
- Ruby 2.4
- Rails 5
- Nginx / Puma
- PostgreSQL

## Development setup

### Docker

Using docker is probably the easiest way to setup your local API if you want to work on mostly front-end part.
Docker should be already installed to follow this process. More info about docker setup is [here](https://docs.docker.com/docker-for-mac/install/).

Run following codes to build docker:

```bash
> docker-compose build
> docker-compose up
```

Then a server is up on `http://localhost:3001`

If you made changes in `bin/start.sh` for DB reset, etc, run following commands again:
```bash
docker-compose build && docker-compose up
```

### Manual Install
If you want to build a local API environment manually on your machine,

First install rbenv and ruby
```bash
brew install rbenv
brew install ruby-build
rbenv install 2.4.2
```

If you don't have PostgresSQL or Node installed on your machine, install it via
```bash
brew install postgresql node
```

Then prepare your dev database:
```bash
PG_UNAME=steemhunt
psql -d postgres -c "CREATE USER $PG_UNAME;"
psql -d postgres -c "ALTER USER $PG_UNAME CREATEDB;"
psql -d postgres -c "ALTER USER $PG_UNAME WITH SUPERUSER;"
```

Then clone the api repo on
`your_path/steemhunt/api`
and web repo on
`your_path/steemhunt/web`

On api repo, install gems
```bash
gem install bundler
bundle install
```

then migrate database
```bash
bundle exec rails db:drop db:create db:migrate db:seed
```

Now you finished installation.

You can start both api and web server by running
```bash
bundle exec rails start
```
