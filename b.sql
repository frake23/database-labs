SELECT DISTINCT teams.*
FROM teams, competitors
WHERE teams.team_id=competitors.team_id
  AND competitors.won=true
GROUP BY teams.team_id

SELECT teams.*
FROM teams, results, games, seasons
WHERE teams.team_id=results.team_id
  AND games.game_id=results.game_id
  AND seasons.season_id=games.season_id
  AND games.stage_info->>'num'='1'
  AND results.succeed=true
GROUP BY teams.team_id