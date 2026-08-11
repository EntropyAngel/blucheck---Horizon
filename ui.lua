--[[
* Addons - Copyright (c) 2021 Ashita Development Team
* Contact: https://www.ashitaxi.com/
* Contact: https://discord.gg/Ashita
*
* This file is part of Ashita.
*
* Ashita is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Ashita is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Ashita.  If not, see <https://www.gnu.org/licenses/>.
--]]

require('common');
local imgui = require('imgui');
local json = require('json');

-- blucheck UI Variables (HorizonXI)
local ui = {
    counts = T{
        known   = 0,
        missing = 0,
        total   = 0,
    },
    data = T{},     -- Raw data loaded from /data/spells.json..
    spells = T{},   -- List of spells with proper data from resources..
    zone = T{},     -- List of spells available in the current zone..

    -- Main Window
    is_open = { false, },

    -- Spells Tab
    tab_spells = {
        selected = { -1, },
    },

    -- Zone Helper Tab
    tab_zonehelper = {
        selected = { -1, },
    },
};

--[[
* Returns the string representation of the given spell type id.
*
* @param {number} t - The spell element type.
* @return {string} The element string.
--]]
function ui.get_spell_element(t)
    return switch(t, {
        [0] = function () return 'Fire'; end,
        [1] = function () return 'Ice'; end,
        [2] = function () return 'Wind'; end,
        [3] = function () return 'Earth'; end,
        [4] = function () return 'Lightning'; end,
        [5] = function () return 'Water'; end,
        [6] = function () return 'Light'; end,
        [7] = function () return 'Dark'; end,
        [15] = function () return '(None)'; end,
        [switch.default] = function () return tostring(t); end
    });
end

-- Returns the spell information block for the given spell.
-- Only HorizonXI spell entries are present in data/spells.json.
function ui.get_spell_data(id)
    local _, v = ui.data:findkey(tostring(id));
    return v or T{};
end

-- HorizonXI learning-source score. Lower scores are preferred.
-- The local database does not contain reliable monster levels, so this uses
-- current-zone preference plus classic/easy-access zone heuristics.
function ui.get_source_score(zoneId, spellLevel, currentZoneId)
    local zid = tonumber(zoneId);
    local current = tonumber(currentZoneId);

    if zid ~= nil and current ~= nil and zid == current then
        return -100000;
    end

    local name = AshitaCore:GetResourceManager():GetString('zones.names', zid) or '';
    local n = name:lower();
    local score = 1000;

    -- Common early/mid-level areas are preferred when otherwise equivalent.
    local easyZones = {
        'ronfaure', 'gustaberg', 'sarutabaruta', 'konschtat', 'la theine',
        'tahrongi', 'jugner', 'batallia', 'sauromogue', 'meriphataud',
        'valkurm', 'buburimu', 'qufim', 'beaucedine', 'yhoator', 'yuhtunga',
        'east ronfaure', 'west ronfaure', 'north gustaberg', 'south gustaberg',
        'east sarutabaruta', 'west sarutabaruta', 'crawler', 'zitah', 'cape teriggan',
        'boyahda', 'den of rancor', 'kuftal', 'bibiki bay', "pso'xja", "ifrit's cauldron"
    };

    for i, token in ipairs(easyZones) do
        if n:find(token, 1, true) ~= nil then
            score = score - (200 - math.min(i, 150));
            break;
        end
    end

    -- Prefer ordinary accessible zones over endgame/NM-heavy locations.
    local difficultZones = {
        'dynamis', 'limbus', 'sea', "al'taieu", "ru'hmet", 'promyvion',
        'sky', "tu'lia", 'temple of uggalepih', 'riverne', 'battlefield',
        'escha', 'reisenjima', 'abyssea', 'adoulin', 'den of rancor'
    };

    for _, token in ipairs(difficultZones) do
        if n:find(token, 1, true) ~= nil then
            score = score + 500;
            break;
        end
    end

    -- Slightly prefer sources that are sensible for the spell's level.
    if tonumber(spellLevel) ~= nil then
        score = score + math.max(0, tonumber(spellLevel) - 50) * 0.25;
    end

    return score;
end

-- Returns the highest-priority HorizonXI learning source for a spell.
function ui.get_recommended_source(spell)
    if spell == nil or spell.zones == nil or spell.zones:len() == 0 then
        return nil, nil, nil;
    end

    local currentZoneId = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    local bestMob = nil;
    local bestZone = nil;
    local bestZoneId = nil;
    local bestScore = math.huge;

    for zoneId, mobs in pairs(spell.zones) do
        local score = ui.get_source_score(zoneId, spell.level, currentZoneId);
        if score < bestScore then
            local mob = nil;
            if type(mobs) == 'table' then
                for _, name in pairs(mobs) do
                    mob = tostring(name);
                    break;
                end
            else
                mob = tostring(mobs);
            end

            if mob ~= nil and mob ~= '' then
                bestScore = score;
                bestMob = mob;
                bestZoneId = tonumber(zoneId);
                bestZone = AshitaCore:GetResourceManager():GetString('zones.names', bestZoneId) or tostring(zoneId);
            end
        end
    end

    return bestMob, bestZone, bestZoneId;
end

--[[
* Updates the list of Blue Mage spell information.
--]]
function ui.get_spells()
    ui.spells = T{};

    -- Build the list of BLU spells..
    for x = 0, 2048 do
        local spell = AshitaCore:GetResourceManager():GetSpellById(x);
        local spell_data = ui.get_spell_data(x);

        -- HorizonXI whitelist:
        -- Only spells explicitly present in data/spells.json are displayed.
        -- This prevents Ashita's retail resource list from adding spells that
        -- exist in the client resources but are not available on HorizonXI.
        if (spell ~= nil
            and spell.Skill == 43
            and spell_data:len() > 0
            and spell.LevelRequired[16 + 1] > 0
            and spell.LevelRequired[16 + 1] <= 75) then
            ui.spells:append(T{
                index   = x,
                name    = spell.Name[1],
                level   = spell.LevelRequired[16 + 1],
                element = spell.Element,
                known   = AshitaCore:GetMemoryManager():GetPlayer():HasSpell(x),
                zones   = spell_data,
            });
        end
    end

    -- Sort the spell list..
    ui.spells:sort(function (a, b)
        return (a.level < b.level) or (a.level == b.level and a.name < b.name);
    end);
end

--[[
* Updates the list of Blue Mage spell information for spells learnable in the current zone.
*
* @param {number} id - The zone id to find spells for.
--]]
function ui.get_zone_spells(id)
    ui.zone = T{};

    local zoneId = tonumber(id);
    if (zoneId == nil or zoneId == 0) then
        return;
    end

    local targetZone = tostring(zoneId);

    -- Build the current-zone spell list directly from the JSON table.
    -- Do not rely on T:each callback argument ordering here; using pairs()
    -- keeps this compatible with Ashita v4 table wrappers and json data.
    for spellId, zoneData in pairs(ui.data) do
        if type(zoneData) == 'table' then
            for sourceZoneId, _ in pairs(zoneData) do
                if tostring(sourceZoneId) == targetZone then
                    for _, spell in ipairs(ui.spells) do
                        if tostring(spell.index) == tostring(spellId) then
                            ui.zone:append(spell);
                            break;
                        end
                    end
                    break;
                end
            end
        end
    end

    -- Sort the zone spell list by level, then name.
    ui.zone:sort(function(a, b)
        return (a.level < b.level) or (a.level == b.level and a.name < b.name);
    end);
end

-- Refresh the Zone Helper from Ashita's live party zone value.
-- This is intentionally called while the UI is open instead of depending
-- only on the zone-enter packet, so the helper remains correct on HorizonXI.
function ui.refresh_zone_helper()
    local zoneId = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    zoneId = tonumber(zoneId) or 0;

    if (ui.current_zone_id ~= zoneId) then
        ui.current_zone_id = zoneId;
        ui.tab_zonehelper.selected[1] = -1;
        ui.get_zone_spells(zoneId);
    end
end

--[[
* Updates the current counts for spells. (Known, missing, and total.)
--]]
function ui.get_spell_counts()
    local counts = T{
        known   = 0,
        missing = 0,
        total   = 0,
    };

    ui.spells:each(function (v, k)
        counts.total = counts.total + 1;

        if (v.known) then
            counts.known = counts.known + 1;
        else
            counts.missing = counts.missing + 1;
        end
    end);

    ui.counts = counts;
end

--[[
* Loads the ui, preparing it for usage.
--]]
function ui.load()
    -- Load the BLU spell list..
    local f = io.open(addon.path .. '/data/spells.json', 'rb');
    if (f == nil) then
        error('Failed to load spell list file. (/data/spells.json)');
    end

    -- Read the full file contents..
    local c = f:read("*all");
    f:close();

    -- Parse the spell json data..
    ui.data = T(json.decode(c) or {});

    -- Load the spell information..
    ui.get_spells();
    ui.get_spell_counts();
    ui.current_zone_id = 0;
    ui.refresh_zone_helper();
end

--[[
* Handles incoming packets to update the ui accordingly.
*
* @param {userdata} e - The packet object.
--]]
function ui.packet_in(e)
    -- Packet: Zone Enter
    if (e.id == 0x000A) then
        ui.tab_zonehelper.selected[1] = -1;
        ui.zone = T{};

        -- Ignore mog house zoning..
        if (struct.unpack('b', e.data_modified, 0x80 + 0x01) == 1) then
            return;
        end

        -- Obtain the zone id..
        local zone = struct.unpack('H', e.data_modified, 0x30 + 1);
        if (zone == 0) then
            zone = struct.unpack('H', e.data_modified, 0x42 + 1);
        end

        -- Update the spell information..
        ui.current_zone_id = tonumber(zone) or 0;
        ui.get_zone_spells(ui.current_zone_id);
        ui.get_spell_counts();

        return;
    end

    -- Packet: Zone Leave
    if (e.id == 0x000B) then
        ui.tab_zonehelper.selected[1] = -1;
        ui.zone = T{};

        return;
    end

    -- Packet: Message Basic
    if (e.id == 0x0029) then
        -- Obtain the message id..
        local msg = struct.unpack('H', e.data_modified, 0x18 + 0x01);
        if (msg == 419) then
            -- Obtain the message information..
            local spellId   = struct.unpack('L', e.data_modified, 0x0C + 0x01);
            local sender    = struct.unpack('H', e.data_modified, 0x14 + 0x01);
            local target    = struct.unpack('H', e.data_modified, 0x16 + 0x01);

            -- Obtain the player entity..
            local player = GetPlayerEntity();
            if (sender == player.TargetIndex and target == player.TargetIndex) then
                -- Mark the spell as known..
                ui.spells:each(function (v, k)
                    if (v.index == spellId) then
                        v.known = true;
                    end
                end);

                -- Update the spell information..
                ui.get_spell_counts();
                ui.refresh_zone_helper();
            end
        end

        return;
    end

    -- Packet: Spells Information
    if (e.id == 0x00AA) then
        ashita.tasks.oncef(1, function ()
            -- Reload the spell information..
            ui.get_spells();
            ui.get_spell_counts();
            ui.refresh_zone_helper();
        end);
        return;
    end
end

--[[
* Renders the right-hand side spell information.
*
* @param {table} lst - The list of data to pull the spell from.
* @param {number} index - The index in the list of data to read the spell from.
--]]
function ui.render_spell_info(lst, index)
    if (index == -1) then
        imgui.TextColored({ 1.0, 1.0, 1.0, 1.0 }, '<< Select a spell for more info.');
    else
        local spell = lst[index];
        local res   = AshitaCore:GetResourceManager():GetSpellById(spell.index);

        if (res == nil) then
            imgui.TextColored({ 1.0, 0.0, 0.0, 1.0 }, 'Failed to obtain spell information.');
        else
            -- Displays a stat value with some color.
            local function showStat(header, value)
                imgui.TextColored({ 1.0, 1.0, 1.0, 1.0 }, header);
                imgui.SameLine();
                imgui.TextColored({ 0.2, 0.7, 1.0, 1.0 }, tostring(value));
            end

            if (imgui.Button('Show Spell On BgWiki')) then
                ashita.misc.open_url(('https://www.bg-wiki.com/ffxi/%s'):fmt(res.Name[1]));
            end

            imgui.PushTextWrapPos(imgui.GetFontSize() * 23.0);
            imgui.TextColored({ 1.0, 0.2, 0.5, 1.0 }, res.Name[1]);
            imgui.TextColored({ 1.0, 0.5, 0.2, 1.0 }, res.Description[1]);
            imgui.PopTextWrapPos();
            imgui.Separator();

            showStat('Index        :', res.Index);
            showStat('Element      :', ui.get_spell_element(res.Element));
            showStat('Mana Cost    :', res.ManaCost);
            showStat('Cast Time    :', ('%.2f sec'):fmt(res.CastTime / 4.0));
            showStat('Recast Delay :', ('%.2f sec'):fmt(res.RecastDelay / 4.0));
            showStat('Level Needed :', res.LevelRequired[16 + 1]);
            showStat('Range        :', ('%d yalms'):fmt(AshitaCore:GetResourceManager():GetSpellRange(res.Index, false)));
            showStat('Area Range   :', ('%d yalms'):fmt(AshitaCore:GetResourceManager():GetSpellRange(res.Index, true)));

            imgui.TextColored({ 1.0, 1.0, 1.0, 1.0 }, 'Known        :');
            imgui.SameLine();
            if (spell.known) then
                imgui.TextColored({ 0.0, 1.0, 0.0, 1.0 }, 'Yes');
            else
                imgui.TextColored({ 1.0, 0.0, 0.0, 1.0 }, 'No');
            end

            imgui.Separator();

            local recommendedMob, recommendedZone, recommendedZoneId = ui.get_recommended_source(spell);
            if recommendedMob ~= nil then
                imgui.TextColored({ 0.2, 1.0, 0.4, 1.0 }, 'HorizonXI Recommended Source');
                imgui.TextColored({ 1.0, 1.0, 1.0, 1.0 }, ('  %s — %s'):fmt(tostring(recommendedMob), tostring(recommendedZone)));
                if tonumber(recommendedZoneId) == tonumber(AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)) then
                    imgui.TextColored({ 0.2, 1.0, 0.4, 1.0 }, '  You are already in this zone.');
                end
                imgui.Separator();
            end

            imgui.TextColored({ 1.0, 1.0, 0.4, 1.0 }, 'Learned From The Following');
            imgui.Separator();

            -- Sort zones so current zone is first
            local currentZoneId = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
            if spell.zones:len() > 0 then
                -- Collect all zone keys
                local zoneKeys = {}
                for k, _ in pairs(spell.zones) do
                    table.insert(zoneKeys, k)
                end
                -- Move current zone to front if present
                table.sort(zoneKeys, function(a, b)
                    local sa = ui.get_source_score(a, spell.level, currentZoneId);
                    local sb = ui.get_source_score(b, spell.level, currentZoneId);
                    if sa == sb then
                        return tonumber(a) < tonumber(b);
                    end
                    return sa < sb;
                end)
                -- Render zones in sorted order
                for _, k in ipairs(zoneKeys) do
                    local v = spell.zones[k]
                    imgui.TextColored({ 1.0, 0.0, 1.0, 1.0 }, AshitaCore:GetResourceManager():GetString('zones.names', tonumber(k)));
                    imgui.Indent();
                    for _, vv in pairs(v) do
                        imgui.TextColored({ 1.0, 1.0, 1.0, 1.0 }, tostring(vv));
                    end
                    imgui.Unindent();
                end
            else
                imgui.TextColored({ 1.0, 0.0, 1.0, 1.0 }, 'No data available.');
            end
        end
    end
end

--[[
* Renders the spell counts.
--]]
function ui.render_spell_counts()
    imgui.TextColored({ 1.0, 1.0, 0.0, 1.0 }, 'Total Spells:');
    imgui.SameLine();
    imgui.TextColored({ 1.0, 0.5, 0.2, 1.0 }, ('%d'):fmt(ui.counts.total));
    imgui.SameLine();
    imgui.TextColored({ 1.0, 1.0, 0.0, 1.0 }, '| Known:');
    imgui.SameLine();
    imgui.TextColored({ 0.2, 1.0, 0.2, 1.0 }, ('%d'):fmt(ui.counts.known));
    imgui.SameLine();
    imgui.TextColored({ 1.0, 1.0, 0.0, 1.0 }, '| Missing:');
    imgui.SameLine();
    imgui.TextColored({ 1.0, 0.2, 0.2, 1.0 }, ('%d'):fmt(ui.counts.missing));
end

--[[
* Renders the spells ui tab.
--]]
function ui.render_tab_spells()
    -- Left Side (Many whelps, handle it!!)
    if ui.hideKnown == nil then ui.hideKnown = false end
    imgui.BeginGroup();
        imgui.TextColored({ 1.0, 0.65, 0.26, 1.0 }, 'Blue Mage Spells');
        imgui.BeginChild('leftpane', { 230, -imgui.GetFrameHeightWithSpacing(), });
            local index = 1;
            ui.spells:each(function (v, k)
                if (ui.hideKnown and v.known) then
                    return
                end
                if (v.known) then
                    imgui.PushStyleColor(ImGuiCol_Text, { 0.0, 1.0, 0.0, 1.0 });
                else
                    imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.0, 0.0, 1.0 });
                end
                if (imgui.Selectable(('[%02d] %s##%d'):fmt(v.level, v.name, v.index), ui.tab_spells.selected[1] == index)) then
                    ui.tab_spells.selected[1] = index;
                end
                imgui.PopStyleColor();

                index = index + 1;
            end);
        imgui.EndChild();

        -- Left side buttons..
        if (imgui.Button('Sort By Level')) then
            ui.spells:sort(function(a, b)
                return (a.level < b.level) or (a.level == b.level and a.name < b.name);
            end);
        end
        imgui.SameLine();
        if (imgui.Button('Sort By Name')) then
            ui.spells:sort(function(a, b)
                return a.name < b.name;
            end);
        end
        
    imgui.EndGroup();
    imgui.SameLine();

    -- Right Side (Key Item Lookup Editor)
    imgui.BeginGroup();
        imgui.TextColored({ 1.0, 0.65, 0.26, 1.0 }, 'Spell Information');
        imgui.BeginChild('rightpane', { 0, -imgui.GetFrameHeightWithSpacing(), });
        -- Adjust index for filtered list
            local filtered = T{}
            ui.spells:each(function(v, k)
                if not (ui.hideKnown and v.known) then
                    filtered:append(v)
                end
            end)
            ui.render_spell_info(ui.spells, ui.tab_spells.selected[1]);
        imgui.EndChild();
        if (imgui.Button('Hide Known Spells')) then
            ui.hideKnown = not ui.hideKnown
            ui.tab_spells.selected[1] = -1
        end
    imgui.EndGroup();
end

--[[
* Renders the zone helper ui tab.
--]]
function ui.render_tab_zonehelper()
    ui.refresh_zone_helper();

    local currentZoneId = ui.current_zone_id or 0;
    local currentZoneName = '';
    if (currentZoneId ~= 0) then
        currentZoneName = AshitaCore:GetResourceManager():GetString('zones.names', currentZoneId) or '';
    end

    imgui.TextColored({ 1.0, 0.65, 0.26, 1.0 }, 'Current Zone:');
    imgui.SameLine();
    imgui.TextColored({ 0.2, 1.0, 0.4, 1.0 }, ('%s [ID %d]'):fmt(currentZoneName ~= '' and currentZoneName or 'Unknown', currentZoneId));
    imgui.TextColored({ 1.0, 1.0, 0.4, 1.0 }, ('BLU spells available here: %d'):fmt(ui.zone:len()));

    -- Left Side (Many whelps, handle it!!)
    imgui.BeginGroup();
        imgui.TextColored({ 1.0, 0.65, 0.26, 1.0 }, 'Zone Spells');
        imgui.BeginChild('leftpane', { 230, -imgui.GetFrameHeightWithSpacing(), });
            local index = 1;
            ui.zone:each(function (v, k)
                if (v.known) then
                    imgui.PushStyleColor(ImGuiCol_Text, { 0.0, 1.0, 0.0, 1.0 });
                else
                    imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.0, 0.0, 1.0 });
                end
                if (imgui.Selectable(('[%02d] %s##%d'):fmt(v.level, v.name, v.index), ui.tab_zonehelper.selected[1] == index)) then
                    ui.tab_zonehelper.selected[1] = index;
                end
                imgui.PopStyleColor();

                index = index + 1;
            end);
        imgui.EndChild();

        -- Left side buttons..
        if (imgui.Button('Sort By Level')) then
            ui.zone:sort(function(a, b)
                return (a.level < b.level) or (a.level == b.level and a.name < b.name);
            end);
        end
        imgui.SameLine();
        if (imgui.Button('Sort By Name')) then
            ui.zone:sort(function(a, b)
                return a.name < b.name;
            end);
        end
    imgui.EndGroup();
    imgui.SameLine();

    -- Right Side (Key Item Lookup Editor)
    imgui.BeginGroup();
        imgui.TextColored({ 1.0, 0.65, 0.26, 1.0 }, 'Spell Information');
        imgui.BeginChild('rightpane', { 0, -imgui.GetFrameHeightWithSpacing(), });
            ui.render_spell_info(ui.zone, ui.tab_zonehelper.selected[1]);
        imgui.EndChild();
    imgui.EndGroup();
end

--[[
* Renders the ui.
--]]
function ui.render()
    -- Skip rendering the ui if it's not open..
    if (not ui.is_open[1]) then
        return;
    end

    -- Render the editor..
    imgui.SetNextWindowSize({ 600, 400, });
    imgui.SetNextWindowSizeConstraints({ 600, 400, }, { FLT_MAX, FLT_MAX, });
    if (imgui.Begin('BluCheck', ui.is_open, ImGuiWindowFlags_NoResize)) then
        ui.render_spell_counts();
        if (imgui.BeginTabBar('##blucheck_tabbar', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton)) then
            if (imgui.BeginTabItem('Spell List', nil)) then
                ui.render_tab_spells();
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Zone Helper', nil)) then
                ui.render_tab_zonehelper();
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end
    end
    imgui.End();
end

-- Return the ui table..
return ui;