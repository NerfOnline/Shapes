addon.name    = 'Shapes';
addon.author  = 'NerfOnline';
addon.version = '0.1';
addon.desc    = 'Marker tool for HorizonXI';

require('common');
local chat = require('chat');
local imgui = require('imgui');
local d3d = require('d3d8');
local ffi = require('ffi');
local bit = require('bit');
local settings = require('settings');
local C = ffi.C;
local d3d8dev = d3d.get_device();

local textures = {};
local assetTextures = {};

local red = { 1.0, 0.2, 0.2, 1.0 };

local defaultSettings = T{
    visible = true,
    locked = false,
    scale = 1.0,
    windowX = 100,
    windowY = 100,
    iconOffsetX = 0,
    iconOffsetY = 0,
    iconScale = 1.0
};
local shapeSettings = settings.load(defaultSettings);

local windowOpen = { shapeSettings.visible };
local iconScale = { shapeSettings.scale }; -- Window icon scale
local markerOffsetX = { shapeSettings.iconOffsetX };
local markerOffsetY = { shapeSettings.iconOffsetY };
local markerScale = { shapeSettings.iconScale };
local showConfig = { false };
local windowLocked = { shapeSettings.locked };
local initialPosSet = false;
local inputModes = {
    windowScale = false,
    windowScaleFocus = false,
    offsetX = false,
    offsetXFocus = false,
    offsetY = false,
    offsetYFocus = false,
    iconScale = false,
    iconScaleFocus = false
};

local ImGuiCond_FirstUseEver = 4;
local ImGuiCond_Always = 1;

-- Groups configuration
-- "groups of 4. starting with number1, number2, number3, and number4, then in next line have the next group be of numbers 5-8, then chains, then stop, then the rest of the leftover images."
local groups = {
    { 'number1', 'number2', 'number3', 'number4' },
    { 'number5', 'number6', 'number7', 'number8' },
    -- Chains (8 total)
    { 'chains1', 'chains2', 'chains3', 'chains4' },
    { 'chains5', 'chains6', 'chains7', 'chains8' },
    -- Stops (8 total)
    { 'stop1', 'stop2', 'stop3', 'stop4' },
    { 'stop5', 'stop6', 'stop7', 'stop8' },
    -- Leftovers
    { 'circle', 'triangle', 'square', 'plus' },
    { 'physical', 'magic', 'ranged', 'special' }
};

local function loadTexture(name)
    if textures[name] then return textures[name] end

    local path = string.format('%smarkers/%s.png', addon.path, name);
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    
    if (C.D3DXCreateTextureFromFileA(d3d8dev, path, texture_ptr) ~= C.S_OK) then
        return nil;
    end
    
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture_ptr[0]));
    textures[name] = texture;
    return texture;
end

local function loadAssetTexture(name)
    if assetTextures[name] then return assetTextures[name] end

    local path = string.format('%sassets/%s.png', addon.path, name);
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');

    if (C.D3DXCreateTextureFromFileA(d3d8dev, path, texture_ptr) ~= C.S_OK) then
        return nil;
    end

    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture_ptr[0]));
    assetTextures[name] = texture;
    return texture;
end

-- Matrix Helper Functions
local function matrixMultiply(m1, m2)
    return ffi.new('D3DXMATRIX', {
        m1._11 * m2._11 + m1._12 * m2._21 + m1._13 * m2._31 + m1._14 * m2._41,
        m1._11 * m2._12 + m1._12 * m2._22 + m1._13 * m2._32 + m1._14 * m2._42,
        m1._11 * m2._13 + m1._12 * m2._23 + m1._13 * m2._33 + m1._14 * m2._43,
        m1._11 * m2._14 + m1._12 * m2._24 + m1._13 * m2._34 + m1._14 * m2._44,
        m1._21 * m2._11 + m1._22 * m2._21 + m1._23 * m2._31 + m1._24 * m2._41,
        m1._21 * m2._12 + m1._22 * m2._22 + m1._23 * m2._32 + m1._24 * m2._42,
        m1._21 * m2._13 + m1._22 * m2._23 + m1._23 * m2._33 + m1._24 * m2._43,
        m1._21 * m2._14 + m1._22 * m2._24 + m1._23 * m2._34 + m1._24 * m2._44,
        m1._31 * m2._11 + m1._32 * m2._21 + m1._33 * m2._31 + m1._34 * m2._41,
        m1._31 * m2._12 + m1._32 * m2._22 + m1._33 * m2._32 + m1._34 * m2._42,
        m1._31 * m2._13 + m1._32 * m2._23 + m1._33 * m2._33 + m1._34 * m2._43,
        m1._31 * m2._14 + m1._32 * m2._24 + m1._33 * m2._34 + m1._34 * m2._44,
        m1._41 * m2._11 + m1._42 * m2._21 + m1._43 * m2._31 + m1._44 * m2._41,
        m1._41 * m2._12 + m1._42 * m2._22 + m1._43 * m2._32 + m1._44 * m2._42,
        m1._41 * m2._13 + m1._42 * m2._23 + m1._43 * m2._33 + m1._44 * m2._43,
        m1._41 * m2._14 + m1._42 * m2._24 + m1._43 * m2._34 + m1._44 * m2._44,
    });
end

local function vec4Transform(v, m)
    return ffi.new('D3DXVECTOR4', {
        m._11 * v.x + m._21 * v.y + m._31 * v.z + m._41 * v.w,
        m._12 * v.x + m._22 * v.y + m._32 * v.z + m._42 * v.w,
        m._13 * v.x + m._23 * v.y + m._33 * v.z + m._43 * v.w,
        m._14 * v.x + m._24 * v.y + m._34 * v.z + m._44 * v.w,
    });
end

local _, viewport = d3d8dev:GetViewport();
local width = viewport.Width;
local height = viewport.Height;

local function worldToScreen(x, y, z, view, projection)
    local vplayer = ffi.new('D3DXVECTOR4', { x, y, z, 1 });
    local viewProj = matrixMultiply(view, projection);
    local pCamera = vec4Transform(vplayer, viewProj);
    local rhw = 1 / pCamera.w;
    local pNDC = ffi.new('D3DXVECTOR3', { pCamera.x * rhw, pCamera.y * rhw, pCamera.z * rhw });
    
    local pRaster = ffi.new('D3DXVECTOR2');
    pRaster.x = math.floor((pNDC.x + 1) * 0.5 * width);
    pRaster.y = math.floor((1 - pNDC.y) * 0.5 * height);
    
    return pRaster.x, pRaster.y, pNDC.z;
end

local function getBone(actorPointer, bone)
    if actorPointer == 0 then return nil, nil, nil end

    local x = ashita.memory.read_float(actorPointer + 0x678);
    local y = ashita.memory.read_float(actorPointer + 0x680);
    local z = ashita.memory.read_float(actorPointer + 0x67C);

    local skeletonBaseAddress = ashita.memory.read_uint32(actorPointer + 0x6B8);
    if skeletonBaseAddress == 0 then return x, y, z end

    local skeletonOffsetAddress = ashita.memory.read_uint32(skeletonBaseAddress + 0x0C);
    if skeletonOffsetAddress == 0 then return x, y, z end

    local skeletonAddress = ashita.memory.read_uint32(skeletonOffsetAddress);
    if skeletonAddress == 0 then return x, y, z end

    local boneCount = ashita.memory.read_uint16(skeletonAddress + 0x32);
    if bone >= boneCount then return x, y, z end

    local bufferPointer = skeletonAddress + 0x30;
    local skeletonSize = 0x04;
    local boneSize = 0x1E;

    local generatorsAddress = bufferPointer + skeletonSize + boneSize * boneCount + 4;

    local dx = ashita.memory.read_float(generatorsAddress + (bone * 0x1A) + 0x0E + 0x0);
    local dy = ashita.memory.read_float(generatorsAddress + (bone * 0x1A) + 0x0E + 0x8);
    local dz = ashita.memory.read_float(generatorsAddress + (bone * 0x1A) + 0x0E + 0x4);

    return x + dx, y + dy, z + dz;
end

local function loadSprite()
    local sprite_ptr = ffi.new('ID3DXSprite*[1]');
    if (C.D3DXCreateSprite(d3d8dev, sprite_ptr) ~= C.S_OK) then
        error('failed to make sprite obj');
    end
    return d3d.gc_safe_release(ffi.cast('ID3DXSprite*', sprite_ptr[0]));
end

local sprite = nil;
local white = d3d.D3DCOLOR_ARGB(255, 255, 255, 255);
local position = ffi.new('D3DXVECTOR2', { 0, 0 });
local scale = ffi.new('D3DXVECTOR2', { 0.5, 0.5 });
local iconOffsetY = 70; -- Higher than job icons to avoid overlap
local iconOffsetX = -8;

local activeMarkers = {}; -- ServerID -> TextureName
local visibleMarkers = {}; -- Index -> TextureName
local lastScan = 0;
local lastZone = 0;

local function getVec2X(v, fallback)
    if type(v) == 'number' then
        return v;
    end

    local ok, r = pcall(function() return v[1]; end);
    if ok and type(r) == 'number' then
        return r;
    end

    ok, r = pcall(function() return v.x; end);
    if ok and type(r) == 'number' then
        return r;
    end

    ok, r = pcall(function() return v.X; end);
    if ok and type(r) == 'number' then
        return r;
    end

    ok, r = pcall(function() return v.width; end);
    if ok and type(r) == 'number' then
        return r;
    end

    return fallback or 0;
end

local function getVec2Y(v, fallback)
    if type(v) == 'number' then
        return v;
    end

    local ok, r = pcall(function() return v[2]; end);
    if ok and type(r) == 'number' then
        return r;
    end

    ok, r = pcall(function() return v.y; end);
    if ok and type(r) == 'number' then
        return r;
    end

    ok, r = pcall(function() return v.Y; end);
    if ok and type(r) == 'number' then
        return r;
    end

    ok, r = pcall(function() return v.height; end);
    if ok and type(r) == 'number' then
        return r;
    end

    return fallback or 0;
end

local function getContentRegionAvailWidth()
    local avail = imgui.GetContentRegionAvail();
    return getVec2X(avail, 0);
end

local function toImTextureId(texture)
    if texture == nil then
        return 0;
    end

    local ok, id = pcall(function()
        return tonumber(ffi.cast('uint32_t', texture));
    end);
    if ok and type(id) == 'number' then
        return id;
    end

    ok, id = pcall(function()
        return tonumber(ffi.cast('uintptr_t', texture));
    end);
    if ok and type(id) == 'number' then
        return id;
    end

    return 0;
end

-- Events
ashita.events.register('load', 'load_cb', function()
    sprite = loadSprite();
end);


-- Main render loop
ashita.events.register('d3d_present', 'present_cb', function()
    -- Check for zoning
    local currentZone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    if currentZone ~= lastZone then
        lastZone = currentZone;
        activeMarkers = {};
        visibleMarkers = {};
        lastScan = 0;
    end

    -- Scan for marker positions periodically (every 0.5s) to avoid iterating 2300 entities every frame
    if os.clock() - lastScan > 0.5 then
        lastScan = os.clock();
        visibleMarkers = {};
        
        if next(activeMarkers) then
            local entity = AshitaCore:GetMemoryManager():GetEntity();
            for i = 0, 2300 do
                local serverID = entity:GetServerId(i);
                if serverID ~= 0 and activeMarkers[serverID] then
                    visibleMarkers[i] = activeMarkers[serverID];
                end
            end
        end
    end

    shapeSettings.visible = windowOpen[1];
    if not windowOpen[1] and not windowLocked[1] and not next(visibleMarkers) then return end
    
    if (windowOpen[1] or windowLocked[1]) then
        local style = imgui.GetStyle();
        local spacingX = style.ItemSpacing.x;
        local spacingY = style.ItemSpacing.y;
        local framePaddingX = style.FramePadding.x;
        local framePaddingY = style.FramePadding.y;

        local scrollbarSize = 10;
        local scrollbarGap = 10; 

        local s = iconScale[1] or 1.0;
        if s < 0.1 then s = 0.1 end
        if s > 5.0 then s = 5.0 end
        iconScale[1] = s;

        local baseIconSize = 42;
        local iconSize = math.floor(baseIconSize * s);
        if iconSize < 16 then iconSize = 16 end
        
        -- ImageButton adds FramePadding on both sides of the image
        local buttonRealWidth = iconSize + (framePaddingX * 2);
        local buttonRealHeight = iconSize + (framePaddingY * 2);

        local cols = 4;
        local rowsVisible = 4;
        
        -- Correct Grid Width Calculation including FramePadding
        local gridWidth = (cols * buttonRealWidth) + ((cols - 1) * spacingX);
        
        -- Height: 4 rows + spacing
        -- Reduced buffer to just 2px for the top dummy.
        local scrollHeight = (rowsVisible * buttonRealHeight) + ((rowsVisible - 1) * spacingY) + 10;
        local footerHeight = math.max(24, math.floor(24 * s)); 

        -- Calculate Child Window Width
        -- Width = Grid + Gap + Scrollbar
        local childWidth = gridWidth + scrollbarGap + scrollbarSize;

        -- Calculate Main Window Width
        -- [WinPadding] [ChildWindow] [WinPadding]
        local paddingX = style.WindowPadding.x;
        local paddingY = style.WindowPadding.y;
        local windowWidth = (paddingX * 2) + childWidth; 
        
        -- Calculate Window Height
        -- TitleBar + PaddingTop + Child + Dummy(4) + Separator(SpacingY) + Footer + PaddingBottom
        -- local titleBarHeight = imgui.GetFontSize() + (style.FramePadding.y * 2); 
        -- Note: Separator + Dummy + spacing logic
        -- We have Dummy(4) + Separator.
        -- local windowHeight = titleBarHeight + (paddingY * 2) + scrollHeight + spacingY + footerHeight + 4;

        -- imgui.SetNextWindowSize({ windowWidth, windowHeight }, ImGuiCond_Always);

        if not initialPosSet then
            imgui.SetNextWindowPos({ shapeSettings.windowX, shapeSettings.windowY }, ImGuiCond_Always);
            initialPosSet = true;
        end

        local autoResize = ImGuiWindowFlags_AlwaysAutoResize or 64;
        local windowFlags = bit.bor(ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoScrollbar, autoResize);
        if windowLocked[1] then
            windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
        end

        local openPtr = windowLocked[1] and nil or windowOpen;
        if (imgui.Begin('Shapes', openPtr, windowFlags)) then
            -- Update settings
            local x, y = imgui.GetWindowPos();
            shapeSettings.windowX = x;
            shapeSettings.windowY = y;
            shapeSettings.scale = iconScale[1];
            shapeSettings.locked = windowLocked[1];
            shapeSettings.visible = windowOpen[1];

            imgui.SetWindowFontScale(s);
            
            imgui.PushStyleVar(ImGuiStyleVar_ScrollbarSize, scrollbarSize);
            imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 2);
            -- Remove padding from child window to ensure exact layout control
            imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
            
            -- Child window for icons
            imgui.BeginChild('##shapes_scroll', { childWidth, scrollHeight }, false, ImGuiWindowFlags_AlwaysVerticalScrollbar);
            
            -- Add a small top margin inside the scroll area so icons aren't glued to the top edge
            imgui.Dummy({0, 2});
            imgui.Indent(4); -- Small left indent for the icons inside the child

            for _, group in ipairs(groups) do
                for i, name in ipairs(group) do
                    local tex = loadTexture(name);
                    if tex then
                        if (i > 1) then imgui.SameLine(); end

                        if (imgui.ImageButton(toImTextureId(tex), { iconSize, iconSize })) then
                            local target = AshitaCore:GetMemoryManager():GetTarget();
                            local targetIndex = target:GetTargetIndex(0);
                            if targetIndex ~= 0 then
                                local entity = AshitaCore:GetMemoryManager():GetEntity();
                                local serverId = entity:GetServerId(targetIndex);
                                if serverId ~= 0 then
                                    if activeMarkers[serverId] == name then
                                        activeMarkers[serverId] = nil;
                                    else
                                        activeMarkers[serverId] = name;
                                    end
                                    lastScan = 0;
                                end
                            end
                        end
                    end
                end
            end
            
            imgui.Unindent(4);
            imgui.EndChild();
            imgui.PopStyleVar(3); -- Pop ScrollbarSize, ScrollbarRounding, WindowPadding
            
            -- Space between grid and footer
            
            -- Footer Layout
            -- Calculate sizes for alignment
            -- ImageButton size = image_size + frame_padding * 2
            -- We want ImageButton height == footerHeight
            -- So image_size = footerHeight - frame_padding * 2
            local footerImageSize = footerHeight - (framePaddingY * 2);
            if footerImageSize < 1 then footerImageSize = 1 end
            
            local iconButtonWidth = footerImageSize + (framePaddingX * 2);
            local rightGroupWidth = (iconButtonWidth * 2) + spacingX;
            
            -- Use childWidth instead of available width to prevent the window from getting stuck at a larger size
            -- when scaling down (AutoResize feedback loop).
            local availWidth = childWidth; 
            local clearAllWidth = availWidth - rightGroupWidth - spacingX;
            
            if clearAllWidth < 10 then clearAllWidth = 10 end

            if (imgui.Button('Clear All', { clearAllWidth, footerHeight })) then
                activeMarkers = {};
                visibleMarkers = {};
                lastScan = 0;
                print(chat.header(addon.name):append(chat.message('All markers cleared.')));
            end

            imgui.SameLine();
            
            -- Right aligned icons: Unlock/Lock then Settings
            local lockName = windowLocked[1] and 'lock' or 'unlock';
            local lockTex = loadAssetTexture(lockName);
            if lockTex and (imgui.ImageButton(toImTextureId(lockTex), { footerImageSize, footerImageSize })) then
                windowLocked[1] = not windowLocked[1];
                if windowLocked[1] then
                    windowOpen[1] = true;
                end
                shapeSettings.locked = windowLocked[1];
                settings.save();
            end

            imgui.SameLine();
            
            local settingsTex = loadAssetTexture('settings');
            if settingsTex and (imgui.ImageButton(toImTextureId(settingsTex), { footerImageSize, footerImageSize })) then
                showConfig[1] = not showConfig[1];
            end
        end
        imgui.End();
    end

    if (showConfig[1]) then
        local autoResize = ImGuiWindowFlags_AlwaysAutoResize or 64;
        local configFlags = bit.bor(ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse, autoResize);
        if (imgui.Begin('Shapes Config', showConfig, configFlags)) then            
            -- Window Settings
            imgui.Text("Window Settings");
            imgui.Separator();
            imgui.Spacing();
            
            imgui.PushItemWidth(120);
            
            -- Window Scale
            local changed = false;
            
            if inputModes.windowScale then
                if not inputModes.windowScaleFocus then
                    imgui.SetKeyboardFocusHere();
                    inputModes.windowScaleFocus = true;
                end
                
                if (imgui.InputFloat('Window Scale', iconScale, 0.1, 1.0, '%.1f', ImGuiInputTextFlags_EnterReturnsTrue)) then
                    changed = true;
                    inputModes.windowScale = false;
                    inputModes.windowScaleFocus = false;
                elseif (imgui.IsItemDeactivated()) then
                    changed = true;
                    inputModes.windowScale = false;
                    inputModes.windowScaleFocus = false;
                end
            else
                if (imgui.SliderFloat('Window Scale', iconScale, 0.1, 5.0, '%.1f')) then
                    changed = true;
                end
                if (imgui.IsItemClicked(1)) then
                    inputModes.windowScale = true;
                    inputModes.windowScaleFocus = false;
                end
            end
            
            if changed then
                shapeSettings.scale = iconScale[1];
                settings.save();
            end
            
            -- Icon Settings
            imgui.Spacing();
            imgui.Text("Icon Settings");
            imgui.Separator();
            imgui.Spacing();
            
            -- Offset X
            changed = false;
            
            if inputModes.offsetX then
                if not inputModes.offsetXFocus then
                    imgui.SetKeyboardFocusHere();
                    inputModes.offsetXFocus = true;
                end
                
                if (imgui.InputFloat('Offset X', markerOffsetX, 1.0, 10.0, '%.0f', ImGuiInputTextFlags_EnterReturnsTrue)) then
                    changed = true;
                    inputModes.offsetX = false;
                    inputModes.offsetXFocus = false;
                elseif (imgui.IsItemDeactivated()) then
                    changed = true;
                    inputModes.offsetX = false;
                    inputModes.offsetXFocus = false;
                end
            else
                if (imgui.SliderFloat('Offset X', markerOffsetX, -200, 200, '%.0f')) then
                    changed = true;
                end
                if (imgui.IsItemClicked(1)) then
                    inputModes.offsetX = true;
                    inputModes.offsetXFocus = false;
                end
            end
            
            if changed then
                shapeSettings.iconOffsetX = markerOffsetX[1];
                settings.save();
            end
            
            -- Offset Y
            changed = false;
            
            if inputModes.offsetY then
                if not inputModes.offsetYFocus then
                    imgui.SetKeyboardFocusHere();
                    inputModes.offsetYFocus = true;
                end
                
                if (imgui.InputFloat('Offset Y', markerOffsetY, 1.0, 10.0, '%.0f', ImGuiInputTextFlags_EnterReturnsTrue)) then
                    changed = true;
                    inputModes.offsetY = false;
                    inputModes.offsetYFocus = false;
                elseif (imgui.IsItemDeactivated()) then
                    changed = true;
                    inputModes.offsetY = false;
                    inputModes.offsetYFocus = false;
                end
            else
                if (imgui.SliderFloat('Offset Y', markerOffsetY, -200, 200, '%.0f')) then
                    changed = true;
                end
                if (imgui.IsItemClicked(1)) then
                    inputModes.offsetY = true;
                    inputModes.offsetYFocus = false;
                end
            end
            
            if changed then
                shapeSettings.iconOffsetY = markerOffsetY[1];
                settings.save();
            end
            
            -- Icon Scale
            changed = false;
            
            if inputModes.iconScale then
                if not inputModes.iconScaleFocus then
                    imgui.SetKeyboardFocusHere();
                    inputModes.iconScaleFocus = true;
                end
                
                if (imgui.InputFloat('Icon Scale', markerScale, 0.1, 1.0, '%.1f', ImGuiInputTextFlags_EnterReturnsTrue)) then
                    changed = true;
                    inputModes.iconScale = false;
                    inputModes.iconScaleFocus = false;
                elseif (imgui.IsItemDeactivated()) then
                    changed = true;
                    inputModes.iconScale = false;
                    inputModes.iconScaleFocus = false;
                end
            else
                if (imgui.SliderFloat('Icon Scale', markerScale, 0.1, 5.0, '%.1f')) then
                    changed = true;
                end
                if (imgui.IsItemClicked(1)) then
                    inputModes.iconScale = true;
                    inputModes.iconScaleFocus = false;
                end
            end
            
            if changed then
                shapeSettings.iconScale = markerScale[1];
                settings.save();
            end

            imgui.PopItemWidth();
        end
        imgui.End();
    end

    -- Render Markers
    if sprite and next(visibleMarkers) then
        local entity = AshitaCore:GetMemoryManager():GetEntity();
        local _, view = d3d8dev:GetTransform(C.D3DTS_VIEW);
        local _, projection = d3d8dev:GetTransform(C.D3DTS_PROJECTION);
        
        sprite:Begin();

        for i, markerName in pairs(visibleMarkers) do
             local tex = loadTexture(markerName);
             if tex then
                  local ptr = entity:GetActorPointer(i);
                  if ptr ~= 0 then
                       -- Bone 2 is usually head/neck
                       local tx, ty, tz = getBone(ptr, 2);
                       local sx, sy, sz = worldToScreen(tx, tz, ty, view, projection);

                       local ms = markerScale[1];
                       scale.x = 0.5 * ms;
                       scale.y = 0.5 * ms;
                       
                       if sz >= 0 and sz <= 1 then
                            local currentWidth = 32 * ms; -- Base size scaled
                            position.x = sx - (currentWidth / 2) + (-8 + markerOffsetX[1]);
                            position.y = sy - (70 + markerOffsetY[1]);
                            sprite:Draw(tex, nil, scale, nil, 0.0, position, white);
                       end
                  end
             end
        end

        sprite:End();
    end
end);

ashita.events.register('unload', 'unload_cb', function()
    settings.save();
end);

-- Command handler
ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args();
    if (#args == 0 or args[1] ~= '/shapes') then
        return;
    end

    -- Toggle Window (No arguments)
    if (#args == 1) then
        if not windowLocked[1] then
            windowOpen[1] = not windowOpen[1];
        else
            windowOpen[1] = true;
        end
        shapeSettings.visible = windowOpen[1];
        settings.save();
        return;
    end

    local action = args[2]:lower();

    -- Clear All
    if (action == 'clear') then
        activeMarkers = {};
        visibleMarkers = {};
        lastScan = 0;
        print(chat.header(addon.name):append(chat.message('All markers cleared.')));
        return;
    end

    -- Shape Logic
    local validShape = false;
    for _, group in ipairs(groups) do
        for _, name in ipairs(group) do
            if name == action then
                validShape = true;
                break;
            end
        end
        if validShape then break; end
    end

    if validShape then
        local target = AshitaCore:GetMemoryManager():GetTarget();
        local targetIndex = target:GetTargetIndex(0);
        
        if targetIndex == 0 then
            print(chat.header(addon.name):append(chat.message('No target selected.')));
            return;
        end
        
        local entity = AshitaCore:GetMemoryManager():GetEntity();
        local serverId = entity:GetServerId(targetIndex);
        
        if serverId == 0 then return; end

        local mode = args[3] and args[3]:lower() or 'toggle';

        if (mode == 'on') then
            activeMarkers[serverId] = action;
        elseif (mode == 'off') then
            if activeMarkers[serverId] == action then
                activeMarkers[serverId] = nil;
            end
        else -- toggle
            if activeMarkers[serverId] == action then
                activeMarkers[serverId] = nil;
            else
                activeMarkers[serverId] = action;
            end
        end
        lastScan = 0;
        return;
    end
end);
