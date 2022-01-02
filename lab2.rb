require 'pg'
require 'faker'

CONN = PG.connect(
  host: 'DESKTOP-4AJHCS9.local',
  port: '5432',
  user: 'postgres',
  password: 'postgres',
  dbname: 'kvn'
)

Faker::UniqueGenerator.clear

# teams table

def team_generator
  i = 0
  -> do
    i += 1
    has_university = Faker::Boolean.boolean
    university = has_university ? Faker::University.unique.name : nil
    city = Faker::Address.city
    name = (university || Faker::Book.title) + ' ' + String(i)
    CONN.exec('INSERT INTO teams (name, city, university) VALUES ($1, $2, $3)', [name, city, university])
    CONN.exec('SELECT * FROM teams WHERE name=$1', [name]).values
  end
end

generate_team = team_generator

# leagues table

(1..10).each do |i|
  name = Faker::Superhero.unique.name + "#{i}"
  address = Faker::Address.full_address
  CONN.exec('INSERT INTO leagues (name, venue_address) VALUES ($1, $2)', [name, address])
end

leagues = CONN.exec('SELECT * FROM leagues').values

# seasons table

leagues.each do |league|
  seasons_count = Faker::Number.between(from: 10, to: 20)
  seasons_years = (0..seasons_count-1).map { |i| i + 1990 }
  seasons_years.each do |year|
    CONN.exec('INSERT INTO seasons (league_id, season_year) VALUES ($1, $2)', [league[0], year])
  end
end



TOURNAMENT_SCHEMAS = [
  {
    count: 15,
    games_count: 9,
    stages_count: 4,
    4 => { total: 15, groups: 3, succeed: 3 },
    3 => { total: 9, groups: 3, succeed: 2 },
    2 => { total: 6, groups: 2,  succeed: 2 },
    1 => { total: 4, groups: 1 }
  },
  {
    count: 12,
    games_count: 9,
    stages_count: 4,
    4 => { total: 12, groups: 3, succeed: 3 },
    3 => { total: 9, groups: 3, succeed: 2 },
    2 => { total: 6, groups: 2,  succeed: 2 },
    1 => { total: 4, groups: 1 }
  },
  {
    count: 9,
    games_count: 8,
    stages_count: 4,
    4 => { total: 9, groups: 3, succeed: 2 },
    3 => { total: 6, groups: 2, succeed: 2 },
    2 => { total: 4, groups: 2, succeed: 1 },
    1 => { total: 2, groups: 1 }
  }
]

seasons_with_teams = []

# teams tables
TEAMS_IN_SEASON = 10

leagues.each do |league|
  schema = TOURNAMENT_SCHEMAS[0]
  new_count = Faker::Number.between(from: 1, to: 3)
  teams = (1..schema[:count] - new_count).map { generate_team.call }
  seasons = CONN.exec('SELECT * FROM seasons WHERE league_id=$1', [league[0]]).values
  seasons.each do |season|
    generated_teams = (1..new_count)
                        .map { generate_team.call }
    season_teams = teams
                     .sample(schema[:count] - new_count)
                     .push(*generated_teams)

    seasons_with_teams << [season, schema, season_teams.map { |team| team[0] }]

    teams = teams.push(*generated_teams)
    new_count = Faker::Number.between(from: 1, to: 3)
    schema = TOURNAMENT_SCHEMAS.sample
  end
end

seasons_with_teams[0]

# games & results tables

seasons_with_teams.each do |season_with_teams|
  season = season_with_teams.first
  year = Integer(season[2])
  date = Faker::Date.in_date_period(year: year, month: 1)
  teams = season_with_teams.last
  schema = season_with_teams[1]

  (0..schema[:stages_count]-2)
   .map do |stage|
     d = date << -stage * 2
     s = schema[:stages_count] - stage
     (1..schema[s][:groups]).map do |group|
       [
         Faker::Book.title,
         d + group * 3,
         s,
         season[0]
       ]
     end
  end
   .reduce([]) { |arr, game| [*arr, *game] }
   .push(
     [
        Faker::Book.title,
        Faker::Date.in_date_period(year: year, month: schema[:stages_count] * 2),
        1,
        season[0]
     ])
   .each { |game| CONN.exec('INSERT INTO games (name, date, stage, season_id) VALUES ($1, $2, $3, $4)', game) }

  games = CONN.exec('SELECT game_id FROM games WHERE season_id = $1 ORDER BY stage', [season[0]]).values.map { |game| game[0] }

  create_game = ->(stage, teams) do
    p stage
    winners = []
    games
      .pop(schema[stage][:groups])
      .each do |game_id|
        winners <<
        teams
          .shift(schema[stage][:total] / schema[stage][:groups])
          .map { |team| [team[0], game_id, false, Faker::Number.between(from: 0, to: 20)] }
          .each { |team| CONN.exec('INSERT INTO results (team_id, game_id, succeed, points) VALUES ($1, $2, $3, $4)', team) }
          .sort { |a, b| a.last <=> b.last }
          .then { |t| stage == 1 ? t.group_by { |a| a.last }.values.last : t.last(schema[stage][:succeed]) }
          .each { |team| CONN.exec('UPDATE results SET succeed=$1 WHERE team_id=$2 AND game_id=$3', [true, team[0], game_id]) }
    end
    winners = winners.reduce([]) { |arr, game| [*arr, *game] }
    stage != 1 && create_game.call(stage-1, winners)
  end
  create_game.call(schema[:stages_count], teams)
  # teams
  #   .map { |team| [team[0], games[0], false, Faker::Number.between(from: 0, to: 20)] }
  #   .each { |team| CONN.exec('INSERT INTO results (team_id, game_id, succeed, points) VALUES ($1, $2, $3, $4)', team) }
  #   .sort { |a, b| a.last <=> b.last }
  #   .last(6)
  #   .each { |team| CONN.exec('UPDATE results SET succeed=$1 WHERE team_id=$2 AND game_id=$3', [true, team[0], games[0]]) }
  #   .map { |team| [team[0], games[1], false, Faker::Number.between(from: 0, to: 20)] }
  #   .each { |team| CONN.exec('INSERT INTO results (team_id, game_id, succeed, points) VALUES ($1, $2, $3, $4)', team) }
  #   .sort { |a, b| a.last <=> b.last }
  #   .last(3)
  #   .each { |team| CONN.exec('UPDATE results SET succeed=$1 WHERE team_id=$2 AND game_id=$3', [true, team[0], games[1]]) }
  #   .map { |team| [team[0], games[2], false, Faker::Number.between(from: 0, to: 20)] }
  #   .each { |team| CONN.exec('INSERT INTO results (team_id, game_id, succeed, points) VALUES ($1, $2, $3, $4)', team) }
  #   .sort { |a, b| a.last <=> b.last }
  #   .last
  #   .then do |last|
  #     CONN.exec('UPDATE results SET succeed=$1 WHERE team_id=$2 AND game_id=$3', [true, last[0], games[2]])
  #     CONN.exec('UPDATE seasons SET team_winner_id=$1 WHERE season_id=$2', [last[0], season[0]])
  #   end
end
