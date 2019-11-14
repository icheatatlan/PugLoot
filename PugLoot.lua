local roll_state = {}
local reset_roll_state = function ()
  roll_state.expecting_self_roll = false
  roll_state.rolling_item = nil
  roll_state.num_members = 0
  roll_state.members = {}
  roll_state.member_rolls = {}
end

reset_roll_state()


local get_announce_target = function (is_roll_msg)
  if IsInRaid() then
    if is_roll_msg and (UnitIsGroupLeader('player') or UnitIsGroupAssistant('player')) then
      return 'RAID_WARNING'
    else
      return 'RAID'
    end
  else
    return 'PARTY'
  end
end

local do_random_loot = function (item_link)
  roll_state.rolling_item = item_link
  roll_state.num_members = GetNumGroupMembers()

  if #roll_state.members > 0 then
    -- print('roll state tainted?', #roll_state.num_members)
  end

  for n = 1, roll_state.num_members do
    local name = GetRaidRosterInfo(n)
    table.insert(roll_state.members, name)
  end
  table.sort(roll_state.members)

  roll_state.expecting_self_roll = true
  RandomRoll(1, roll_state.num_members)
end

local do_start_roll = function(item_link, duration)
  roll_state.rolling_item = item_link
  roll_state.num_members = GetNumGroupMembers()

  for n = 1, roll_state.num_members do
    local name = GetRaidRosterInfo(n)
    table.insert(roll_state.members, name)
  end

  SendChatMessage('ROLL ' .. item_link .. ' (' .. tostring(duration) .. ' seconds)', get_announce_target(true), nil, nil)

  C_Timer.NewTimer(duration, function ()
    local max_roll = 0
    local highest_rollers = {}
    local sorted_rolls = {}

    for name, roll in pairs(roll_state.member_rolls) do
      if roll > max_roll then
        max_roll = roll
        highest_rollers = {}
        table.insert(highest_rollers, name)
      elseif roll == max_roll then
        table.insert(highest_rollers, name)
      end

      table.insert(sorted_rolls, { name = name, roll = roll })
    end

    table.sort(sorted_rolls, function (a, b)
      return a.roll > b.roll
    end)

    if #highest_rollers == 0 then
      SendChatMessage('Nobody rolled for ' .. roll_state.rolling_item .. '!', get_announce_target(false), nil, nil)
    elseif #highest_rollers == 1 then
      SendChatMessage(highest_rollers[1] .. ' wins ' .. roll_state.rolling_item .. ' with a ' .. max_roll, get_announce_target(false), nil, nil)
    else
      local tied_rollers = 'Tie:'
      for _, name in ipairs(highest_rollers) do
        tied_rollers = tied_rollers .. ' ' .. name
      end

      SendChatMessage(tied_rollers .. ' (' .. max_roll .. ')', get_announce_target(false), nil, nil)
    end

    if #sorted_rolls > 0 then
      -- truncate to ensure the chat message length limit isn't exceeded
      while (#sorted_rolls > 5) do
        table.remove(sorted_rolls, #sorted_rolls)
      end

      local summary = 'Rolls:'
      for _, roll in ipairs(sorted_rolls) do
        summary = summary .. ' ' .. roll.name .. ' (' .. tostring(roll.roll) .. ')'
      end

      SendChatMessage(summary, get_announce_target(false), nil, nil)
    end

    reset_roll_state()
  end)
end

local frame = CreateFrame('frame', 'PugLootEventFrame')
frame:RegisterEvent('CHAT_MSG_SYSTEM')
frame:SetScript('OnEvent', function (self, event, ...)
  local msg = ...

  -- copied from Raid Roll - https://www.curseforge.com/wow/addons/raid-roll
  -- Convert Blizzard locale specific print string for roll chat messages to a regex to parse them.
  -- Since the first term is the character name and character names with realms can contain spaces,
  -- we'll look for a message that ends with this regex.
  -- I'm assuming this is correct because the previous code pulled the character name from
  -- the first word of the message, but for cross-realm characters with multi-word realm names,
  -- we need a stronger solution.
  local _rollMessageTailRegex =
      RANDOM_ROLL_RESULT               -- The enUS value is "%s rolls %d (%d-%d)"
                                       -- The German value is "%1$s würfelt. Ergebnis: %2$d (%3$d-%4$d)"
          :gsub("%(", "%%(")           -- Open paren escaped for regex
          :gsub("%)", "%%)")           -- Close paren escaped for regex
          :gsub("%%d", "(%%d+)")       -- Convert %d for printing integer to sequence of digits
          :gsub("%%%d+%$d", "(%%d+)")  -- Convert positional %#$d for printing integer to sequence of digits
          :gsub("%%s", "")             -- Delete %s for character name
          :gsub("%%%d+%$s", "")        -- Delete positional %#$s for character name
          .. "$"                       -- End of line anchor for regex

  local roll, min, max = msg:match(_rollMessageTailRegex)
  local name = msg:gsub("%s*" .. _rollMessageTailRegex, "")

  if not name or not roll or not min or not max then
    return
  end

  roll = tonumber(roll, 10)
  min = tonumber(min, 10)
  max = tonumber(max, 10)

  if roll_state.expecting_self_roll and name == GetUnitName("player", false) then
    if min == 1 and max == roll_state.num_members then
      local winner = roll_state.members[roll]
      SendChatMessage(winner .. ' wins ' .. roll_state.rolling_item .. ' (#' .. tostring(roll) .. ')', get_announce_target(false), nil, nil)
    end

    reset_roll_state()
  elseif roll_state.rolling_item and min == 1 and max == 100 and not roll_state.member_rolls[name] then
    local is_member = false
    for _, group_member in ipairs(roll_state.members) do
      if name == group_member then
        is_member = true
      end
    end

    if is_member then
      -- print('added roll', name, roll, min, max)
      roll_state.member_rolls[name] = roll
    end
  end
end)


SLASH_PUGLOOT1 = "/pugloot"
SlashCmdList["PUGLOOT"] = function (arg_str)
  if not IsInRaid() and not IsInGroup() then
    print('You are not in a raid/group')
    return
  end

  local cmd = nil
  local rest = nil

  local space = arg_str:find(' ')
  if space then
    cmd = arg_str:sub(1, space - 1)
    rest = arg_str:sub(space + 1)
  else
    cmd = arg_str
  end

  if cmd == 'random' and rest then
    if not roll_state.rolling_item then
      do_random_loot(rest)
    else
      print('There is an ongoing roll for ' .. roll_state.rolling_item)
    end
  elseif cmd == 'start' and rest then
    if not roll_state.rolling_item then
      do_start_roll(rest, 15)
    else
      print('There is an ongoing roll for ' .. roll_state.rolling_item)
    end
  else
    print('Usage: /pugloot random [item] | /pugloot start [item]')
  end
end

