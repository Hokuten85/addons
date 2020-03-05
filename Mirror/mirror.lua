_addon.name = 'Mirror';
_addon.version = '1.6';
_addon.author = 'Hokuten';
_addon.commands = {'mirror', 'mr' };

require('luau')
require('pack');
packets=require('packets')
res = require 'resources'
--config = require('config')

-- defaults = {
-- }

-- settings = config.load(defaults)

local self = windower.ffxi.get_player();
local mirror;
local slaveIsLocal = false;
local masterIsLocal = false;
local slaves = {};
local handshakeInProgress = false;
local lastPacketTime = os.time();

local approach = false;
local meleeDistance = 3.0;
local runningDirection;
local followIndex;

local follow = false;

local spells = {}
local jobAbilities = {}

function endHandshake()
    handshakeInProgress = false;
end

function sendHandshake(mob)
    handshakeInProgress = true
    windower.send_ipc_message(string.format("command:mirror|id:%s|targetid:%s",self.id,mob.id))
end

function sendStop(mob)
    windower.send_ipc_message(string.format("command:stop|id:%s",self.id))
end

function isSlaveLocal()
    local isLocal = false;
    for key,value in pairs(slaves) do
        if (value) then
            isLocal = true;
        end
    end
    
    slaveIsLocal = isLocal;
end

function isSlaveClose()
    local isClose = false;
    for key,value in pairs(slaves) do
        if (value) then
            local slave = windower.ffxi.get_mob_by_id(key)
            if (slave.distance <= 900) then
                isClose = true;
            end
        end
    end
    
    return isClose;
end

function split(msg, match)
    if msg == nil then return '' end
    local length = msg:len()
    local splitarr = {}
    local u = 1
    while u <= length do
        local nextanch = msg:find(match,u)
        if nextanch ~= nil then
            splitarr[#splitarr+1] = msg:sub(u,nextanch-match:len())
            if nextanch~=length then
                u = nextanch+match:len()
            else
                u = length
            end
        else
            splitarr[#splitarr+1] = msg:sub(u,length)
            u = length+1
        end
    end
    return splitarr
end

--string.format("Packet Key: %s, Inventory Slot: %s, Item Name: %s\n", tostring(key), tostring(value), tostring(itemName)))

windower.register_event('load',function()
    for key,value in pairs(res.spells) do
        spells[value.en:lower()] = {id = value.id, range = value.range};
    end
    
    for key,value in pairs(res.job_abilities) do
        jobAbilities[value.en:lower()] = {id = value.id, range = value.range};
    end
end)

---------------------------------------------------------------------------------------------------
-- func: addon command
-- desc: Called when our addon receives a command.
---------------------------------------------------------------------------------------------------
windower.register_event('addon command', function (command, ...)
    local args = T{...}
    if type(command) == 'string' then
        if (command:lower() == 'approach') then
            if (args[1] == 'on') then
                approach = true;
            elseif (args[1] == 'off') then
                approach = false;
            elseif (args[1] == nil) then
                approach = not approach;
            end
            
            notice("Approach set to " .. tostring(approach))
            
            return
        elseif (command:lower() == 'distance') then
            if (args[1] ~= nil) then
                meleeDistance = tonumber(args[1]);
            end
            
            notice("Melee Distance set to " .. tostring(meleeDistance))
            
            return
        elseif (command:lower() == 'follow') then
            if (args[1] == 'on') then
                follow = true;
            elseif (args[1] == 'off') then
                follow = false;
            elseif (args[1] == nil) then
                follow = not follow;
            end
            
            notice("Follow set to " .. tostring(follow))
            
            return
        end
    
        local mob = windower.ffxi.get_mob_by_name(command)
        if (mob and self.id == mob.id) then
            windower.add_to_chat(207, 'Cannot mirror self.')
            return
        end
        
        if (mob and mob.id) then
            if (mob.in_party and not mob.is_npc) then
                mirror = mob
                masterIsLocal = false;
                sendHandshake(mirror);
                coroutine.schedule(endHandshake, 3)
                windower.add_to_chat(207, 'Now mirroring ' .. mob.name ..'.')
            elseif (mob.is_npc) then
                windower.add_to_chat(207, mob.name..' is an NPC.')
            elseif (not mob.in_party) then
                windower.add_to_chat(207, mob.name..' not in party.')
            else
                windower.add_to_chat(207, 'Could not find entity to mirror.')
            end
        elseif (command:lower() == 'action') then
            if args[1] then
                local type = args[1]:lower()
                local param
                if (args[2]) then
                    param = args[2]:lower() -- Job Ability or Pet Ability or Spell Name
                end
                
                if type == 'ja' or type == 'pet' or type == 'ma' or type == 'ra' then
                    local category, actionParam, range;
                    if (type == 'ja' or type == 'pet') and jobAbilities[param] then
                        category = 0x09
                        actionParam = jobAbilities[param].id
                        range = jobAbilities[param].range
                    elseif type == 'ma' and spells[param] then
                        category = 0x03
                        actionParam = spells[param].id
                        range = spells[param].range
                    elseif type == 'ra' then
                        category = 0x10
                        actionParam = 0
                        range = 24
                    else
                        windower.add_to_chat(207, 'Mirror could not find a matching spell or ability.')
                    end
                    if category and (actionParam or type == 'ra') and range then
                        self = windower.ffxi.get_player();
                        local target, target_index
                        if range == 0 then
                            target = windower.ffxi.get_mob_by_index(self.index)
                            target_index = self.index
                        elseif (self.target_index) then
                            target = windower.ffxi.get_mob_by_index(self.target_index)
                            target_index = self.target_index
                        end 
                        if target then
                            action(category,target.id,target_index,actionParam)
                            windower.send_ipc_message(string.format("command:action|id:%s|targetid:%s|targetindex:%s|category:%s|actionparam:%s",self.id,target.id,target_index,category,actionParam))
                        end
                    end
                else
                    windower.add_to_chat(207, 'Mirror only supports action types of ja, pet, and ma')
                end
            end
        elseif (command:lower() == 'stop') then
            sendStop(mirror)
            mirror = nil
            masterIsLocal = false;
            windower.add_to_chat(207, 'Stopping mirror.')
        else
            windower.add_to_chat(207, 'Could not find entity to mirror.')
        end
    end
end);

---------------------------------------------------------------------------------------------------
-- func: incoming chunk
-- desc: Called when our addon receives an incoming chunk.
---------------------------------------------------------------------------------------------------
windower.register_event('incoming chunk', function(id, original, modified, injected, blocked)
    -- check to see if the incoming packet is an event packet
    if (id == 0x00D and mirror and not handshakeInProgress and not masterIsLocal) then
        local inPacket = packets.parse('incoming', original)
        if (inPacket.Player == mirror.id and (inPacket['Update Vitals'] or inPacket['Update Position'])) then
            local newMirror = windower.ffxi.get_mob_by_id(mirror.id)
            if (newMirror and newMirror.id and newMirror.in_party) then
                if (mirror.status ~= newMirror.status or mirror.target_index ~= newMirror.target_index) then
                    local mob = windower.ffxi.get_mob_by_index(newMirror.target_index)
                    if (mob and mob.is_npc) then
                    
                        if (mirror.status ~= newMirror.status ) then
                            if (newMirror.status == 1) then
                                action(0x02,mob.id,mob.index)
                            elseif (newMirror.status == 0) then
                                action(0x04,self.id,self.index)
                            end
                        elseif (mirror.target_index ~= newMirror.target_index and newMirror.status == 1) then
                            action(0x0F,mob.id,mob.index)
                        end
                    end

                    mirror = newMirror
                end
            end
        end
    end
end);

function action(category, targetid, targetindex, actionparam, controlFrequency)
    if (not controlFrequency or (controlFrequency and os.time() > lastPacketTime)) then -- should help restrict the frequency that packets are spammed when necessary
        lastPacketTime = os.time();
    
        local actionPacket = {}
        
        actionPacket["Target"] = targetid
        actionPacket["Target Index"] = targetindex
        actionPacket["Category"] = category
        actionPacket["Param"] = actionparam
        actionPacket["_unknown1"] = 0
        actionPacket["X Offset"] = 0
        actionPacket["Z Offset"] = 0
        actionPacket["Y Offset"] = 0
        
        packets.inject(packets.new('outgoing', 0x01A, actionPacket))
    end
end

windower.register_event('ipc message',function (msg)
    local splitMsg = split(msg, '|')
    local params = {}
    for key,value in pairs(splitMsg) do
        local param = split(value, ':')
        params[param[1]] = param[2];
    end
    
    if (params.command) then
        self = windower.ffxi.get_player();
        if (params.command == 'action') then
            if (params.targetid and params.targetindex and params.category) then
                local actionParam = params.actionparam or 0
                if params.id == params.targetid then
                    params.targetid = self.id
                    params.targetindex = self.index
                end
                
                action(params.category,params.targetid,params.targetindex,actionParam)
            end
        elseif (params.command == 'mirror') then
            if (params.id and params.targetid) then
                slaves[params.id] = tonumber(params.targetid) == tonumber(self.id);
            end
            
            isSlaveLocal();
            
            windower.send_ipc_message(string.format("command:acknowledge|id:%s",self.id))
        elseif (params.command == 'acknowledge') then
            if (tonumber(params.id) == tonumber(mirror.id)) then
                masterIsLocal = true;
            end
        elseif (params.command == 'stop') then
            if (params.id) then
                slaves[params.id] = false;
                isSlaveLocal();
            end
        end
    end
end)

windower.register_event('outgoing chunk',function (id, original, modified, injected, blocked)
    if (id == 0x01A and slaveIsLocal) then
        local outPacket = packets.parse('outgoing', original)
        if ((outPacket.Category == 2 or outPacket.Category == 4 or outPacket.Category == 15) and isSlaveClose()) then
            windower.send_ipc_message(string.format("command:action|id:%s|targetid:%s|targetindex:%s|category:%s|actionparam:%s",self.id,outPacket.Target,outPacket['Target Index'],outPacket.Category,outPacket.Param))
        end
    end
end)

windower.register_event('unload','logout',function ()
    sendStop(mirror)
end)

function runTo()
    local player = windower.ffxi.get_mob_by_id(self.id);
    local mob = windower.ffxi.get_mob_by_target('t');
    
    local angle = math.atan2((mob.y - player.y), (mob.x - player.x)) * -1
    windower.ffxi.run(angle)
end

function runAway()
    local player = windower.ffxi.get_mob_by_id(self.id);
    local mob = windower.ffxi.get_mob_by_index(self.target_index);
    
    local angle = (math.atan2((mob.y - player.y), (mob.x - player.x))*180/math.pi)*-1
    windower.ffxi.run((angle+180):radian())        
end

function faceMob()
    local player = windower.ffxi.get_mob_by_id(self.id);
    local mob = windower.ffxi.get_mob_by_target('t');
    local angle = math.atan2((mob.y - player.y), (mob.x - player.x)) * -1
    windower.ffxi.turn(angle);
end

windower.register_event('prerender', function()
    if (approach) then
        self = windower.ffxi.get_player()
        if (self.status == 1) then -- if engaged
            if (self.follow_index and self.follow_index ~= self.index) then
                followIndex = self.follow_index;
                windower.ffxi.follow(self.index); -- stop following if following
                windower.ffxi.run(false);
            end
            
            local mob = windower.ffxi.get_mob_by_target('t');
            if (mob and mob.valid_target) then
                if (mob.distance:sqrt() > meleeDistance) then
                    runTo();
                else
                    windower.ffxi.run(false);
                    faceMob();
                end
            else
                windower.ffxi.run(false);
            end
        elseif (self.status == 0 and follow) then -- if idle
            if (followIndex) then
                windower.ffxi.follow(followIndex);
                followIndex = nil;
            end
        end
    elseif (mirror and not handshakeInProgress) then
        self = windower.ffxi.get_player();
        local newMirror = windower.ffxi.get_mob_by_id(mirror.id)
        if (newMirror ~= nil and newMirror.status == 1 and self.status == 0) then
            local mob = windower.ffxi.get_mob_by_index(newMirror.target_index)
            if (mob and mob.is_npc) then
                action(0x02,mob.id,mob.index,0,true)
            end
            
            mirror = newMirror
        end
    end
end)
