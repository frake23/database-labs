require 'pg'
require 'faker'

CONN = PG.connect(
  host: 'DESKTOP-4AJHCS9.local',
  port: '5432',
  user: 'postgres',
  password: 'postgres',
  dbname: 'kvn3'
)

# teams table

def team_generator
  i = 0
  -> do
    i += 1
    has_university = Faker::Boolean.boolean
    university = has_university ? Faker::University.unique.name : nil
    city = Faker::Address.city
    name = (university || Faker::Book.title) + " #{i}"
    CONN.exec('INSERT INTO teams (name, city, university) VALUES ($1, $2, $3)', [name, city, university])
    Faker::UniqueGenerator.clear if i % 60 == 0
    CONN.exec('SELECT * FROM teams WHERE name=$1', [name]).values
  end
end

generate_team = team_generator

# leagues table

(1..5000).each do |i|
  name = Faker::Superhero.name + " #{i}"
  address = Faker::Address.full_address
  information = Faker::Lorem.paragraph
  CONN.exec('INSERT INTO leagues (name, venue_address, information) VALUES ($1, $2, $3)', [name, address, information])
end

leagues = CONN.exec('SELECT * FROM leagues').values

# seasons table

leagues.each do |league|
  first = Faker::Number.between(from: 1920, to: 1935)
  (first..2021).each do |year|
    CONN.exec('INSERT INTO seasons (league_id, season_year) VALUES ($1, $2)', [league[0], year])
  end
end

def create_competitions(count)
  (1..count).map do
    {
      name: Faker::Lorem.word,
      max_points: Faker::Number.between(from: 3, to: 6)
    }
  end
end

TOURNAMENT_SCHEMAS = [
  {
    teams_count: 20,
    stages_count: 4,
    games_count: 12,
    4 => { num: 4, total: 20, groups: 5, succeed: 3 },
    3 => { num: 3, total: 15, groups: 3, succeed: 3 },
    2 => { num: 2, total: 9, groups: 3, succeed: 1 },
    1 => { num: 1, total: 3, groups: 1, succeed: nil }
  },
  {
    teams_count: 15,
    stages_count: 4,
    games_count: 9,
    4 => { num: 4, total: 15, groups: 3, succeed: 3 },
    3 => { num: 3, total: 9, groups: 3, succeed: 2 },
    2 => { num: 2, total: 6, groups: 2, succeed: 2 },
    1 => { num: 1, total: 4, groups: 1, succeed: nil }
  },
  {
    teams_count: 12,
    stages_count: 4,
    games_count: 9,
    4 => { num: 4, total: 12, groups: 3, succeed: 3 },
    3 => { num: 3, total: 9, groups: 3, succeed: 2 },
    2 => { num: 2, total: 6, groups: 2, succeed: 2 },
    1 => { num: 1, total: 4, groups: 1, succeed: nil }
  },
  {
    teams_count: 9,
    stages_count: 4,
    games_count: 8,
    4 => { num: 4, total: 9, groups: 3, succeed: 2 },
    3 => { num: 3, total: 6, groups: 2, succeed: 2 },
    2 => { num: 2, total: 4, groups: 2, succeed: 1 },
    1 => { num: 1, total: 2, groups: 1, succeed: nil }
  }
]

seasons_with_teams = []

# teams tables
TEAMS_IN_SEASON = 10

leagues.each do |league|
  schema = TOURNAMENT_SCHEMAS[0]
  new_count = Faker::Number.between(from: 1, to: 3)
  teams = (1..schema[:teams_count] - new_count).map { generate_team.call }
  seasons = CONN.exec('SELECT * FROM seasons WHERE league_id=$1', [league[0]]).values
  seasons.each do |season|
    CONN.exec('UPDATE seasons SET schema=$1 WHERE season_id=$2', [schema.slice(:teams_count, :stages_count, :games_count).to_json, season[0]])
    generated_teams = (1..new_count)
                        .map { generate_team.call }
    season_teams = teams
                     .sample(schema[:teams_count] - new_count)
                     .push(*generated_teams)

    seasons_with_teams << [season, schema, season_teams.map { |team| team[0] }]

    teams = teams.push(*generated_teams)
    new_count = Faker::Number.between(from: 1, to: 3)
    schema = TOURNAMENT_SCHEMAS.sample
  end
end

# games & results tables

seasons_with_teams.each do |season_with_teams|
  season = season_with_teams.first
  p season[0]
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
        season[0],
        schema[s].merge!({competitions: create_competitions(5)}).to_json
      ]
    end
  end
    .reduce([]) { |arr, game| [*arr, *game] }
    .push(
      [
        Faker::Book.title,
        Faker::Date.in_date_period(year: year, month: schema[:stages_count] * 2),
        season[0],
        schema[1].merge!({competitions: create_competitions(7)}).to_json
      ])
    .then { |games|
      values = (0..games.length-1).map do |i|
        k = i * 4
        "($#{k + 1}, $#{k + 2}, $#{k + 3}, $#{k + 4})"
      end.join(', ')
      CONN.exec("INSERT INTO games (name, date, season_id, stage_info) VALUES #{values}", games.reduce([]) { |arr, a| [*arr, *a] })
    }

  games = CONN.exec("SELECT game_id, stage_info->>'num' as num FROM games WHERE season_id = $1 ORDER BY num", [season[0]]).values.map { |game| game[0] }

  teams
    .map{ |team| [team[0], season[0]] }
    .then do |ts|
      values = (0..ts.length-1).map do |i|
        k = i * 2
        "($#{k + 1}, $#{k + 2})"
      end.join(', ')
      CONN.exec("INSERT INTO competitors (team_id, season_id) VALUES #{values}", ts.reduce([]) { |arr, a| [*arr, *a] })
    end

  create_game = ->(stage, teams) do
    winners = []
    games
      .pop(schema[stage][:groups])
      .each do |game_id|
      winners <<
        teams
          .shift(schema[stage][:total] / schema[stage][:groups])
          .map do |team|
            points = schema[stage][:competitions].map { |comp| Faker::Number.between(from: 0, to: comp[:max_points]) }
            [team[0], game_id, false, points.sum, "{#{points.join(', ')}}" ]
          end
          .then do |ts|
            values = (0..ts.length-1).map do |i|
              k = i * 5
              "($#{k + 1}, $#{k + 2}, $#{k + 3}, $#{k + 4}, $#{k + 5})"
            end.join(', ')
            CONN.exec("INSERT INTO results (team_id, game_id, succeed, points, competitions_points) VALUES #{values}", ts.reduce([]) { |arr, a| [*arr, *a] })
            ts
          end
          .sort { |a, b| a.last <=> b.last }
          .then { |t| stage == 1 ? t.group_by { |a| a.last }.values.last : t.last(schema[stage][:succeed]) }
          .each do |team|
            CONN.exec('UPDATE results SET succeed=$1 WHERE team_id=$2 AND game_id=$3', [true, team[0], game_id])
            CONN.exec('UPDATE competitors SET won=true WHERE team_id=$1 AND season_id=$2', [team[0], season[0]]) if stage == 1
          end
    end
    winners = winners.reduce([]) { |arr, game| [*arr, *game] }
    stage != 1 && create_game.call(stage-1, winners)
  end
  create_game.call(schema[:stages_count], teams)
end