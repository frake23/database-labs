create sequence league_league_id_seq
    as integer;

alter sequence league_league_id_seq owner to postgres;

create table if not exists teams
(
    team_id    serial
    constraint teams_pk
    primary key,
    name       varchar not null,
    city       varchar not null,
    university varchar
);

alter table teams
    owner to postgres;

create unique index if not exists teams_name_uindex
    on teams (name);

create table if not exists leagues
(
    league_id     integer default nextval('league_league_id_seq'::regclass) not null
    constraint league_pk
    primary key,
    name          varchar                                                   not null,
    venue_address varchar                                                   not null
    );

alter table leagues
    owner to postgres;

alter sequence league_league_id_seq owned by leagues.league_id;

create unique index if not exists leagues_name_uindex
    on leagues (name);

create table if not exists seasons
(
    season_id   serial
    constraint seasons_pk
    primary key,
    league_id   integer not null
    constraint seasons_leagues_league_id_fk
    references leagues,
    season_year integer not null
);

alter table seasons
    owner to postgres;

create table if not exists games
(
    game_id   serial
    constraint games_pk
    primary key,
    name      varchar           not null,
    date      date              not null,
    stage     integer default 3 not null,
    season_id integer           not null
    constraint games_seasons_season_id_fk
    references seasons
);

alter table games
    owner to postgres;

create table if not exists results
(
    team_id integer               not null
    constraint results_teams_team_id_fk
    references teams,
    game_id integer               not null
    constraint results_games_game_id_fk
    references games,
    points  integer               not null,
    succeed boolean default false not null,
    constraint results_pk
    primary key (game_id, team_id)
    );

alter table results
    owner to postgres;