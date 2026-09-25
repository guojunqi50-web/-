-- CT 授权+功能二合一（放在直链上，大小不受限）
local RK="__CT_AUTH"
local R=rawget(_G,RK) or {}
rawset(_G,RK,R)
R.done=R.done==true

local VK="wumai8865464"
local SF="/storage/emulated/0/Android/data/com.tencent.mf.uam/files/ct.txt"

local function trim(s) return tostring(s or ""):gsub("^%s+",""):gsub("%s+$","") end
local function sr(n) local ok,r=pcall(require,n) if ok then return r end end
local function wc(w,m,...) if w and type(w[m])=="function" then return pcall(w[m],w,...) end end
local function stext(w,t)
  if not w then return end
  for _,m in ipairs({"SetText","SetContentText","SetTitleText","SetHintText","SetButtonText"}) do
    if wc(w,m,t) then return end
  end
end
local function hide(w)
  if not w then return end
  wc(w,"SetIsEnabled",false); wc(w,"SetRenderOpacity",0)
  if UE4 and UE4.ESlateVisibility and w.SetVisibility then pcall(w.SetVisibility,w,UE4.ESlateVisibility.Collapsed) end
end
local function tip(t,d)
  if UABoot and UABoot.TipManager and type(UABoot.TipManager.Toast)=="function" then
    pcall(UABoot.TipManager.Toast,UABoot.TipManager,{content=tostring(t),duration=d or 2})
  end
end

local function load_k()
  if UE4 and UE4.UBFLPlatformFile and type(UE4.UBFLPlatformFile.LoadFileToString)=="function" then
    local ok,d=pcall(UE4.UBFLPlatformFile.LoadFileToString,SF)
    if ok and type(d)=="string" then return trim(d) end
  end
  local f=io and io.open and io.open(SF,"rb")
  if f then local d=f:read("*a") f:close() return trim(d) end
  return ""
end
local function save_k(k)
  if UE4 and UE4.UBFLPlatformFile and type(UE4.UBFLPlatformFile.SaveStringToFile)=="function" then
    pcall(UE4.UBFLPlatformFile.SaveStringToFile,trim(k),SF) return
  end
  local f=io and io.open and io.open(SF,"wb")
  if f then f:write(trim(k)) f:close() end
end

-- 产品脚本源码（授权通过后load执行）
local PRODUCT_SRC=[==[
-- CT 三角洲行动 透视+自瞄 v60（120fps流畅+自瞄+去人机）
local state = _G.CTWallhack or {}
_G.CTWallhack = state

local CONFIG = {
  scan_period = 0.15,        -- 扫描：6.7fps
  render_period = 0.008,     -- 渲染：125fps（方框流畅）
  aim_period = 0.016,        -- 自瞄：60fps
  max_targets = 100,
  box_alpha = 0.3,
  mat_inner_alpha = 0.7,
  box_offset_x = 0,
  box_offset_y = 6,
  box_width_scale = 0.45,
  color_player = {r=1.0, g=0.0, b=0.0},  -- 真人红
  color_ai = {r=0.0, g=0.4, b=1.0},      -- 人机蓝
  color_occluded = {r=1.0, g=0.8, b=0.0}, -- 掩体后黄色
  -- 自瞄配置
  aim_enabled = true,
  aim_range = 300,
  aim_strength = 0.4,
  aim_smooth = 0.25,
  aim_max_distance = 15000,
  aim_include_ai = true,
  aim_debug_mark = true,
  mat_paths = {
    china = "/Game/ArtResource/MaterialLibrary/tkMaterialLibrary/MasterMaterials/Character/CharacterEffect/M_FX_InvisibleMonster.M_FX_InvisibleMonster",
    oversea = "/Game/ArtResource/MaterialLibrary/tkMaterialLibrary/MasterMaterials/Character/CharacterEffect/M_FX_InvisibleMonster_Dying.M_FX_InvisibleMonster_Dying",
  },
}

local UE4 = _G.UE4
local tracked = {}
local mat_applied = {}
local esp_boxes = {}
local base_mat = nil
local is_oversea = false
local canvas_cache = nil
local enemy_cache = {}
local scan_timer = 0
local viewport_w = 1920
local viewport_h = 1080
local ui_scale_x = 1.0
local ui_scale_y = 1.0
local aspect_ratio = 1.78
local is_tablet = false
local viewport_update_timer = 0

local function sc(fn, ...)
  local ok, r = pcall(fn, ...)
  if ok then return r end
  return nil
end

local function is_valid(obj)
  if not obj then return false end
  local ok, v = pcall(UE4.UObject.IsValid, obj)
  return ok and v == true
end

local function get_world()
  return sc(function()
    if _G.GetCurrentWorld then return _G.GetCurrentWorld() end
    return nil
  end)
end

-- 分辨率适配（宽高比自适应，平板手机分别处理）
local function update_viewport_size()
  local world = get_world()
  if not world then return end
  sc(function()
    if UE4.UWidgetLayoutLibrary then
      local sz = UE4.UWidgetLayoutLibrary.GetViewportSize(world)
      if sz and sz.X and sz.Y and sz.X > 0 then
        viewport_w = sz.X
        viewport_h = sz.Y
      end
    end
  end)
  sc(function()
    local pc = UE4.UGameplayStatics.GetPlayerController(world, 0)
    if is_valid(pc) then
      local w, h = pc:GetViewportSize()
      if w and w > 0 then
        viewport_w = w
        viewport_h = h
      end
    end
  end)
  -- 计算宽高比
  if viewport_h > 0 then
    aspect_ratio = viewport_w / viewport_h
  end
  -- 平板判断：宽高比 < 1.5 视为平板
  is_tablet = aspect_ratio < 1.5
  -- x方向scale基于宽度（基准1920）
  ui_scale_x = viewport_w / 1920.0
  if ui_scale_x < 0.5 then ui_scale_x = 0.5 end
  if ui_scale_x > 2.0 then ui_scale_x = 2.0 end
  -- y方向scale基于高度（基准1080）
  ui_scale_y = viewport_h / 1080.0
  if ui_scale_y < 0.5 then ui_scale_y = 0.5 end
  if ui_scale_y > 2.0 then ui_scale_y = 2.0 end
end

local function check_oversea()
  is_oversea = sc(function()
    if _G.UABoot and _G.UABoot.AppDataModel then
      return _G.UABoot.AppDataModel.bIsOverseaVersion == true
    end
    return false
  end) or false
end

local function load_material()
  if is_valid(base_mat) then return end
  check_oversea()
  local path = is_oversea and CONFIG.mat_paths.oversea or CONFIG.mat_paths.china
  base_mat = sc(function() return UE4.UObject.Load(path) end)
end

local function apply_mesh_mat(mesh, color)
  if not is_valid(mesh) then return end
  sc(function() mesh.bRenderCustomDepth = true; mesh.CustomDepthStencilValue = 1 end)
  sc(function()
    local num = mesh:GetNumMaterials() or 0
    local col = UE4.FLinearColor(color.r, color.g, color.b, 1)
    for i = 0, num - 1 do
      local mid = mesh:CreateDynamicMaterialInstance(i, base_mat)
      if is_valid(mid) then
        mid:SetScalarParameterValue("IfUseCameraClip", 0.0)
        mid:SetScalarParameterValue("InnerAlpha", CONFIG.mat_inner_alpha)
        mid:SetScalarParameterValue("LineAlpha", 1.0)
        mid:SetScalarParameterValue("EdgeWidth", 0.8)
        mid:SetScalarParameterValue("ThermalView_InvisibleEnabled", 0.0)
        mid:SetScalarParameterValue("ThermalView_InstanceEnabled", 1.0)
        mid:SetVectorParameterValue("ColorMul", col)
        mid:SetVectorParameterValue("OutlineColor", col)
      end
    end
  end)
end

-- 掩体判断：从相机到目标头部做LineTrace，被挡住则返回true
local function is_occluded(world, target_head)
  local pc = sc(function() return UE4.UGameplayStatics.GetPlayerController(world, 0) end)
  if not is_valid(pc) then return false end
  local cam_loc = sc(function()
    local cm = pc:GetPlayerCameraManager()
    return is_valid(cm) and cm:GetCameraLocation() or nil
  end)
  if not cam_loc or not target_head then return false end
  local hit = sc(function()
    local hit_result = UE4.FHitResult()
    local params = UE4.FTraceQueryParams()
    if params then
      params.bTraceComplex = false
      params.bReturnFaceIndex = false
    end
    local ok = UE4.UKismetSystemLibrary.LineTraceSingle(
      world, cam_loc, target_head,
      UE4.ETraceTypeQuery.Visibility,
      false, {}, UE4.EDrawDebugTrace.None,
      hit_result, true
    )
    return ok and hit_result and hit_result.bBlockingHit
  end)
  return hit == true
end

local function apply_character_mat(char, color)
  local ok1 = sc(function()
    local skels = char:K2_GetComponentsByClass(UE4.USkeletalMeshComponent:StaticClass())
    if skels then for i = 1, skels:Length() do apply_mesh_mat(skels:Get(i), color) end end
    return true
  end)
  local ok2 = sc(function()
    local statics = char:K2_GetComponentsByClass(UE4.UStaticMeshComponent:StaticClass())
    if statics then for i = 1, statics:Length() do apply_mesh_mat(statics:Get(i), color) end end
    return true
  end)
  return ok1 or ok2
end

local function get_canvas()
  if canvas_cache and is_valid(canvas_cache) then return canvas_cache end
  local world = get_world()
  if not world then return nil end

  -- 方式1：UUserWidget + AddToViewport，强制设置位置(0,0)和全屏大小
  local uw = sc(function()
    if UE4.UWidgetBlueprintLibrary then
      local w = UE4.UWidgetBlueprintLibrary.Create(world, UE4.UUserWidget.StaticClass())
      if is_valid(w) then
        w:AddToViewport(10000)
        -- 强制设置widget在视口(0,0)位置，避免安全区域偏移
        pcall(function() w:SetPositionInViewport(UE4.FVector2D(0, 0), false) end)
        pcall(function()
          local vw, vh = get_viewport_size(world)
          if vw and vh then w:SetDesiredSizeInViewport(UE4.FVector2D(vw, vh)) end
        end)
        -- 设置Anchors为全屏
        pcall(function()
          if w.Slot then
            local a = UE4.FAnchors()
            a.Minimum.X=0; a.Minimum.Y=0; a.Maximum.X=1; a.Maximum.Y=1
            w.Slot:SetAnchors(a)
            w.Slot:SetOffsets(UE4.FMargin(0,0,0,0))
          end
        end)
        return w
      end
    end
    return nil
  end)
  if is_valid(uw) then
    local c = sc(function() return uw.RootCanvas end)
    if is_valid(c) then
      -- 强制RootCanvas也全屏
      pcall(function()
        if c.Slot then
          local a = UE4.FAnchors()
          a.Minimum.X=0; a.Minimum.Y=0; a.Maximum.X=1; a.Maximum.Y=1
          c.Slot:SetAnchors(a)
        end
      end)
      canvas_cache = c; return c
    end
  end

  -- 方式2：直接创建CanvasPanel + AddViewportWidgetContent（绕过UUserWidget安全区域）
  local direct_canvas = sc(function()
    local c = UE4.UGameplayStatics.SpawnObject(UE4.UCanvasPanel.StaticClass(), world)
    if is_valid(c) then
      if UE4.UGameplayStatics and UE4.UGameplayStatics.GetPlayerController then
        local pc = UE4.UGameplayStatics.GetPlayerController(world, 0)
        if is_valid(pc) and pc.AddViewportWidgetContent then
          pc:AddViewportWidgetContent(c, 10000)
          return c
        end
      end
      -- 备选：通过GameInstance添加
      local gi = UE4.UGameplayStatics.GetGameInstance(world)
      if gi and gi.AddViewportWidgetContent then
        gi:AddViewportWidgetContent(c, 10000)
        return c
      end
    end
    return nil
  end)
  if is_valid(direct_canvas) then
    canvas_cache = direct_canvas; return direct_canvas
  end

  -- 方式3：旧方式兜底
  local root = sc(function() return _G.UABoot and _G.UABoot.PanelManager and _G.UABoot.PanelManager:GetTopRootCanvas() end)
  local c2 = sc(function() return root and root.RootCanvas or root end)
  if is_valid(c2) then canvas_cache = c2; return c2 end
  return nil
end

local function create_box(canvas)
  local world = get_world()
  local b = sc(function() return UE4.UGameplayStatics.SpawnObject(UE4.UBorder.StaticClass(), world or canvas) end)
  if not is_valid(b) then return nil end
  sc(function()
    canvas:AddChild(b)
    b:SetVisibility(UE4.ESlateVisibility.HitTestInvisible)
    b:SetBrushColor(UE4.FLinearColor(1, 0, 0, CONFIG.box_alpha))
    local slot = b.Slot
    if slot then
      if slot.SetAnchors then
        local a = UE4.FAnchors(); a.Minimum.X=0; a.Minimum.Y=0; a.Maximum.X=0; a.Maximum.Y=0
        slot:SetAnchors(a)
      end
      if slot.SetAlignment then slot:SetAlignment(UE4.FVector2D(0, 0)) end
      if slot.SetZOrder then slot:SetZOrder(60000) end
    end
  end)
  return b
end

local function get_or_create_box(key, canvas)
  local box = esp_boxes[key]
  if box and is_valid(box) then return box end
  box = create_box(canvas)
  if box then esp_boxes[key] = box end
  return box
end

local function set_box(box, x, y, w, h, r, g, b, a)
  sc(function()
    local slot = box.Slot
    if slot then
      if slot.SetPosition then slot:SetPosition(UE4.FVector2D(x, y)) end
      if slot.SetSize then slot:SetSize(UE4.FVector2D(w, h)) end
    end
    box:SetBrushColor(UE4.FLinearColor(r, g, b, a))
    box:SetVisibility(UE4.ESlateVisibility.HitTestInvisible)
  end)
end

-- 获取DPI scale：多种方式兜底，不缓存（避免缓存错误结果）
local function get_dpi_scale(world)
  local dpi = nil
  -- 方式1：UWidgetLayoutLibrary
  sc(function()
    if UE4.UWidgetLayoutLibrary and UE4.UWidgetLayoutLibrary.GetViewportScale then
      dpi = UE4.UWidgetLayoutLibrary.GetViewportScale(world)
    end
  end)
  -- 方式2：通过LocalPlayer获取
  if not dpi or dpi <= 0 then
    sc(function()
      local gi = UE4.UGameplayStatics.GetGameInstance(world)
      if gi and gi.GetFirstLocalPlayer then
        local lp = gi:GetFirstLocalPlayer()
        if lp and lp.GetViewportClient then
          local vc = lp:GetViewportClient()
          if vc and vc.GetDPIScale then
            dpi = vc:GetDPIScale()
          end
        end
      end
    end)
  end
  -- 方式3：通过PlayerController获取
  if not dpi or dpi <= 0 then
    sc(function()
      local pc = UE4.UGameplayStatics.GetPlayerController(world, 0)
      if pc and pc.GetPlayerCameraManager then
        local cm = pc:GetPlayerCameraManager()
        if cm then
          -- 有些游戏通过CameraManager的FOV和视口大小推算DPI
        end
      end
    end)
  end
  return dpi
end

-- 获取视口逻辑大小
local function get_viewport_size(world)
  local vw, vh = nil, nil
  sc(function()
    if UE4.UWidgetLayoutLibrary and UE4.UWidgetLayoutLibrary.GetViewportSize then
      local size = UE4.UWidgetLayoutLibrary.GetViewportSize(world)
      if size then
        vw, vh = size.X, size.Y
      end
    end
  end)
  if not vw then
    sc(function()
      local pc = UE4.UGameplayStatics.GetPlayerController(world, 0)
      if pc and pc.GetViewportSize then
        vw, vh = pc:GetViewportSize()
      end
    end)
  end
  return vw, vh
end

local function w2s(world, loc)
  if not world or not loc then return nil end
  local sx, sy = nil, nil

  -- 优先用false投影（绝对像素），然后用视口大小推算DPI转换
  -- false一定返回绝对像素，比true更可靠（true在不同设备行为不一致）
  local ok2, s2, sl2 = pcall(function()
    return UE4.UKismetMathLibrary.ProjectWorldLocationToScreen(world, loc, false)
  end)
  if ok2 and sl2 and sl2.X then
    sx, sy = sl2.X, sl2.Y
  elseif ok2 and s2 and type(s2) == "userdata" and s2.X then
    sx, sy = s2.X, s2.Y
  end

  if sx then
    -- 用视口逻辑大小推算DPI：绝对像素 / 逻辑宽度 = DPI scale
    local vw, vh = get_viewport_size(world)
    if vw and vw > 0 then
      local dpi = get_dpi_scale(world)
      if dpi and dpi > 1.01 then
        sx = sx / dpi
        sy = sy / dpi
      else
        -- DPI获取失败，用投影坐标和视口宽度推算
        -- 如果投影坐标明显大于视口宽度，说明是绝对像素
        if sx > vw * 1.1 then
          local est = sx / vw
          if est > 1.1 then
            sx = sx / est
            sy = sy / est
          end
        end
      end
    end
  end

  -- 备选：true投影（逻辑坐标，不需要转换）
  if not sx then
    local ok1, s1, sl1 = pcall(function()
      return UE4.UKismetMathLibrary.ProjectWorldLocationToScreen(world, loc, true)
    end)
    if ok1 and sl1 and sl1.X then sx, sy = sl1.X, sl1.Y end
    if ok1 and s1 and type(s1) == "userdata" and s1.X then sx, sy = s1.X, s1.Y end
  end

  -- 备选：PlayerController
  if not sx then
    local pc = sc(function() return UE4.UGameplayStatics.GetPlayerController(world, 0) end)
    if is_valid(pc) then
      local ok3, p3, sl3 = pcall(function() return pc:ProjectWorldLocationToScreen(loc, true) end)
      if ok3 and sl3 and sl3.X then sx, sy = sl3.X, sl3.Y end
      if ok3 and p3 and type(p3) == "userdata" and p3.X then sx, sy = p3.X, p3.Y end
    end
  end

  if not sx then return nil end
  return sx, sy
end

local function get_head(char)
  -- 头部位置：降低到真实头部中心（胶囊全高 - 40）
  local head_z = 130
  sc(function()
    local cap = char:GetCapsuleComponent()
    if is_valid(cap) then
      local hh = cap:GetScaledCapsuleHalfHeight()
      if hh and hh > 0 then
        head_z = hh * 2 - 40
      end
    end
  end)
  local b = sc(function() local loc = char:K2_GetActorLocation(); return loc and loc.X and loc or nil end)
  if b then
    b.Z = (b.Z or 0) + head_z
    return b
  end
  local l = sc(function()
    local m = char:GetMesh()
    if is_valid(m) then
      local h = m:GetSocketLocation("head")
      if h and h.X then return h end
      h = m:GetSocketLocation("Head")
      if h and h.X then return h end
    end
    return nil
  end)
  if l and l.X then return l end
  return nil
end

local function get_feet(char)
  -- 用actor location（胶囊体底部），远点更稳定
  return sc(function() local loc = char:K2_GetActorLocation(); return loc and loc.X and loc or nil end)
end

local function get_local_pawn(world)
  return sc(function()
    local p = UE4.USGPlayerStatics.GetLocalPlayerCharacter(world)
    return is_valid(p) and p or nil
  end)
end

local function is_dead(c)
  if sc(function() return UE4.USGActorStatics.IsDead(c) end) then return true end
  if sc(function() return UE4.USGCharacterStatics.IsDBNO(c) end) then return true end
  return false
end

local function is_target(c, lp)
  if not is_valid(c) then return false end
  if c == lp then return false end
  -- 严格排除自身：通过对象地址、PlayerState、Controller多重判断
  if is_valid(lp) then
    if sc(function() return c:GetPlayerState() == lp:GetPlayerState() end) then return false end
    if sc(function() return c:GetController() == lp:GetController() end) then return false end
  end
  if is_dead(c) then return false end
  if is_valid(lp) and sc(function() return UE4.USGTeamStatics.OnSameTeam(lp, c) end) then return false end
  return true
end

local function check_is_ai(char)
  if sc(function() return char:IsA(UE4.ASGAICharacter:StaticClass()) end) then return true end
  local cls_name = sc(function()
    local cls = char:GetClass()
    return cls and cls:GetName() or ""
  end)
  if cls_name and (cls_name:find("AI") or cls_name:find("Bot") or cls_name:find("Monster") or cls_name:find("NPC")) then return true end
  local has_ai_ctrl = sc(function()
    local ctrl = char:GetController()
    if not ctrl then return false end
    local cn = ctrl:GetClass():GetName()
    return cn and (cn:find("AI") or cn:find("AIController") or cn:find("Bot"))
  end)
  if has_ai_ctrl then return true end
  return false
end

-- 严格角色验证：必须是ASGCharacter（真人玩家），且有有效骨骼网格
-- 排除ASGAICharacter（人机）
local function is_valid_character(a)
  if not is_valid(a) then return false end
  local is_sg = sc(function() return a:IsA(UE4.ASGCharacter:StaticClass()) end)
  if not is_sg then return false end
  -- 双重保险：排除AI
  if check_is_ai(a) then return false end
  local has_mesh = sc(function()
    local m = a:GetMesh()
    return is_valid(m)
  end)
  if not has_mesh then
    has_mesh = sc(function()
      local sk = a:K2_GetComponentsByClass(UE4.USkeletalMeshComponent:StaticClass())
      return sk and sk:Length() > 0
    end)
  end
  return has_mesh == true
end

local function scan(world)
  local lp = get_local_pawn(world)
  enemy_cache = {}
  -- 先收集人机（标记is_ai=true）
  local ai_arr = sc(function() return UE4.UGameplayStatics.GetAllActorsOfClass(world, UE4.ASGAICharacter:StaticClass()) end)
  local ai_keys = {}
  if ai_arr and ai_arr.Length then
    for i = 1, ai_arr:Length() do
      local a = sc(function() return ai_arr:Get(i) end)
      if is_valid(a) then
        local key = tostring(a)
        ai_keys[key] = true
        if not tracked[key] then
          tracked[key] = { char = a, is_ai = true, trust = 0, miss = 0 }
        else
          tracked[key].is_ai = true
        end
      end
    end
  end
  -- 再收集真人（排除已标记为AI的）
  local arr = sc(function() return UE4.UGameplayStatics.GetAllActorsOfClass(world, UE4.ASGCharacter:StaticClass()) end)
  if arr and arr.Length then
    for i = 1, arr:Length() do
      local a = sc(function() return arr:Get(i) end)
      if is_valid_character(a) then
        local key = tostring(a)
        if not ai_keys[key] then
          if not tracked[key] then
            tracked[key] = { char = a, is_ai = false, trust = 0, miss = 0 }
          else
            tracked[key].is_ai = false
          end
        end
      end
    end
  end
  local count = 0
  for key, data in pairs(tracked) do
    local char = data.char
    if not is_valid(char) then
      data.miss = (data.miss or 0) + 1
      if data.miss >= 3 then
        tracked[key] = nil
        mat_applied[key] = nil
      end
    elseif is_target(char, lp) then
      data.trust = (data.trust or 0) + 1
      data.miss = 0
      -- 每帧更新材质颜色（掩体判断）
      local head = get_head(char)
      local occluded = head and is_occluded(world, head) or false
      data.occluded = occluded
      local base_color = data.is_ai and CONFIG.color_ai or CONFIG.color_player
      local c = occluded and CONFIG.color_occluded or base_color
      -- 只在首次或颜色变化时应用材质
      if not mat_applied[key] or data.last_color_key ~= tostring(occluded) then
        local ok = apply_character_mat(char, c)
        if ok then
          mat_applied[key] = true
          data.last_color_key = tostring(occluded)
        end
      end
      if count < CONFIG.max_targets then
        enemy_cache[key] = data
        count = count + 1
      end
    elseif data.trust and data.trust >= 3 then
      data.miss = (data.miss or 0) + 1
      if data.miss < 5 then
        if count < CONFIG.max_targets then
          enemy_cache[key] = data
          count = count + 1
        end
      else
        tracked[key] = nil
        mat_applied[key] = nil
      end
    elseif is_dead(char) then
      data.miss = (data.miss or 0) + 1
      if data.miss >= 2 then
        tracked[key] = nil
        mat_applied[key] = nil
      end
    else
      tracked[key] = nil
      mat_applied[key] = nil
    end
  end
end

local function render_boxes(world)
  local canvas = get_canvas()
  if not canvas then return end
  local visible = {}
  -- 画点：真人红点、人机蓝点（不画方框）
  for key, data in pairs(enemy_cache) do
    local char = data.char
    if is_valid(char) then
      local head = get_head(char)
      if head then
        local hx, hy = w2s(world, head)
        if hx and hy then
          local base_c = data.is_ai and CONFIG.color_ai or CONFIG.color_player
          local c = data.occluded and CONFIG.color_occluded or base_c
          local box = get_or_create_box(key, canvas)
          if box then
            set_box(box, hx - 5, hy - 5, 10, 10, c.r, c.g, c.b, 0.9)
          end
          visible[key] = true
        end
      end
    end
  end
  for key, box in pairs(esp_boxes) do
    if not visible[key] and is_valid(box) then
      sc(function() box:SetVisibility(UE4.ESlateVisibility.Collapsed) end)
    end
  end
end

-- ========== 自瞄 ==========
local aim_target = nil
local aim_debug_box = nil
local cross_debug_box = nil

local function aim_get_pc(world)
  return sc(function() return UE4.UGameplayStatics.GetPlayerController(world, 0) end)
end

local function aim_get_cam_loc(world)
  local pc = aim_get_pc(world)
  if not is_valid(pc) then return nil end
  return sc(function()
    local cm = pc:GetPlayerCameraManager()
    return is_valid(cm) and cm:GetCameraLocation() or nil
  end)
end

local function aim_norm(a)
  while a > 180 do a = a - 360 end
  while a < -180 do a = a + 360 end
  return a
end

-- 自瞄直接用透视已收集的tracked表（最可靠，不重新收集）
local aim_debug_boxes = {}

local function aim_find_target(world)
  if not CONFIG.aim_enabled then return nil end
  local vw, vh = get_viewport_size(world)
  local cx, cy = (vw or 1280) / 2, (vh or 720) / 2
  local best, best_d = nil, CONFIG.aim_range
  local count = 0
  local valid_head = 0
  local valid_screen = 0

  -- 直接遍历透视收集的tracked表（不用goto，不用own排除）
  for key, info in pairs(tracked) do
    count = count + 1
    local char = info.char
    if is_valid(char) then
      local head = info.head
      if not head then
        head = get_head(char)
        info.head = head
      end
      if head then
        valid_head = valid_head + 1
        local hx, hy = w2s(world, head)
        if hx and hy then
          valid_screen = valid_screen + 1
          local sd = math.sqrt((hx - cx)^2 + (hy - cy)^2)
          if sd < best_d then
            best_d = sd
            best = { char = char, head = head, sx = hx, sy = hy }
          end
        end
      end
    end
  end
  return best
end

local function do_aimbot(world)
  if not CONFIG.aim_enabled then return end
  local canvas = get_canvas()
  if not canvas then return end
  local vw, vh = get_viewport_size(world)
  local cx = (vw or 1280) / 2
  local cy = (vh or 720) / 2

  -- 每帧先隐藏所有旧点（避免叠在一起）
  for i = 1, #aim_debug_boxes do
    if aim_debug_boxes[i] and is_valid(aim_debug_boxes[i]) then
      sc(function() aim_debug_boxes[i]:SetVisibility(UE4.ESlateVisibility.Collapsed) end)
    end
  end

  -- 准心黄点
  if CONFIG.aim_debug_mark then
    if not cross_debug_box or not is_valid(cross_debug_box) then cross_debug_box = create_box(canvas) end
    if cross_debug_box then
      set_box(cross_debug_box, cx - 4, cy - 4, 8, 8, 1, 1, 0, 0.9)
    end
  end

  -- 遍历tracked（真人+人机）
  local best_head = nil
  local best_sx, best_sy = 0, 0
  local best_dist = 400
  local idx = 0

  for key, info in pairs(tracked) do
    local char = info.char
    if not is_valid(char) then goto cont end
    local head = info.head
    if not head then
      head = get_head(char)
      info.head = head
    end
    if not head then goto cont end
    local hx, hy = w2s(world, head)
    if not hx or not hy then goto cont end
    -- 点标记
    if CONFIG.aim_debug_mark then
      idx = idx + 1
      local box = aim_debug_boxes[idx]
      if not box or not is_valid(box) then
        box = create_box(canvas)
        aim_debug_boxes[idx] = box
      end
      if box then
        if info.is_ai then
          set_box(box, hx - 6, hy - 6, 12, 12, 0, 0.3, 1, 0.9)  -- 人机蓝
        else
          set_box(box, hx - 6, hy - 6, 12, 12, 1, 0, 0, 0.9)  -- 真人红
        end
      end
    end
    -- 目标选择
    local sd = math.sqrt((hx - cx)^2 + (hy - cy)^2)
    if sd < best_dist then
      best_dist = sd
      best_head = head
      best_sx = hx
      best_sy = hy
    end
    ::cont::
  end

  -- 没目标
  if not best_head then
    if aim_debug_box and is_valid(aim_debug_box) then
      sc(function() aim_debug_box:SetVisibility(UE4.ESlateVisibility.Collapsed) end)
    end
    return
  end

  -- 锁定目标绿点
  if CONFIG.aim_debug_mark then
    if not aim_debug_box or not is_valid(aim_debug_box) then
      aim_debug_box = create_box(canvas)
    end
    if aim_debug_box then
      set_box(aim_debug_box, best_sx - 9, best_sy - 9, 18, 18, 0, 1, 0, 0.95)
    end
  end

  -- 视角吸附：只用AddYawInput/AddPitchInput（模拟玩家输入，最可靠）
  local pc = aim_get_pc(world)
  if not is_valid(pc) then return end
  local cur = sc(function() return pc:GetControlRotation() end)
  if not cur then return end
  local cam_loc = aim_get_cam_loc(world)
  if not cam_loc then return end

  local tgt = sc(function() return UE4.UKismetMathLibrary.FindLookAtRotation(cam_loc, best_head) end)
  if not tgt then
    tgt = sc(function() return UE4.UKismetMathLibrary.GetLookAtRotation(cam_loc, best_head) end)
  end
  if not tgt then return end

  local yd = aim_norm(tgt.Yaw - cur.Yaw)
  local pd = aim_norm(tgt.Pitch - cur.Pitch)

  -- 方式1：直接SetControlRotation（不用RLerp，直接设置目标角度）
  sc(function()
    pc:SetControlRotation(tgt)
  end)
  -- 方式2：AddYawInput高强度（备用）
  sc(function()
    if pc.AddYawInput then pc:AddYawInput(yd * 3.0) end
    if pc.AddPitchInput then pc:AddPitchInput(pd * 3.0) end
  end)
  -- 方式3：修改Pawn的ViewRotation（备用）
  sc(function()
    local pawn = pc:GetPawn()
    if is_valid(pawn) and pawn.SetViewRotation then
      pawn:SetViewRotation(tgt, false)
    end
  end)
end

-- 分阶段初始化，避免启动卡顿
local init_phase = 0
local init_frame = 0

function state:tick()
  sc(function()
    local world = get_world()
    if not world then return end

    viewport_update_timer = viewport_update_timer + CONFIG.render_period
    if viewport_update_timer >= 5.0 then
      viewport_update_timer = 0
      update_viewport_size()
    end

    if init_phase < 3 then
      init_frame = init_frame + 1
      if init_phase == 0 then
        if _G.UABoot and _G.UABoot.PanelManager then
          update_viewport_size()
          init_phase = 1
          init_frame = 0
        end
        return
      elseif init_phase == 1 and init_frame >= 30 then
        if not is_valid(base_mat) then load_material() end
        if is_valid(base_mat) then
          init_phase = 2
          init_frame = 0
          sc(function() UE4.UKismetSystemLibrary.ExecuteConsoleCommand(world, "r.CustomDepth 3") end)
        end
        return
      elseif init_phase == 2 and init_frame >= 15 then
        init_phase = 3
        scan(world)
      end
      return
    end

    if not is_valid(base_mat) then load_material() end
    -- 扫描：低频率
    scan_timer = scan_timer + CONFIG.render_period
    if scan_timer >= CONFIG.scan_period then
      scan_timer = 0
      scan(world)
    end
    -- 渲染：120fps
    render_boxes(world)
    -- 自瞄：60fps
    aim_timer = (aim_timer or 0) + CONFIG.render_period
    if aim_timer >= CONFIG.aim_period then
      aim_timer = 0
      do_aimbot(world)
    end
  end)
end

function state:init()
  if self.timer and _G.TimerSys then
    sc(function() _G.TimerSys:UnRegistedTimer(self.timer) end)
    self.timer = nil
  end
  canvas_cache = nil
  base_mat = nil
  tracked = {}
  esp_boxes = {}
  mat_applied = {}
  enemy_cache = {}
  scan_timer = 0
  init_phase = 0
  init_frame = 0
  viewport_update_timer = 0
  if _G.TimerSys then
    sc(function()
      self.timer = _G.TimerSys:RegistedRepeatTimeTimer("CTWallhack_Tick", self, state.tick, 0, CONFIG.render_period, _G.TimerSys.INFINITE_LENGTH, self)
    end)
  end
end

state:init()
]==]

local function start_product()
  local fn=load(PRODUCT_SRC,"ct_product","bt",_G)
  if fn then pcall(fn) end
end

local function configure(panel)
  if not panel or not panel.bind then return end
  R.panel=panel
  local b=panel.bind
  if b.InputTextBox then wc(b.InputTextBox,"SetText",""); wc(b.InputTextBox,"SetHintText","请输入授权码") end
  stext(b.TitleText or b.Text_Title or b.Txt_Title,"CT授权验证")
  stext(b.ContentText or b.Text_Content or b.TxtContent,"欢迎使用CT，请输入授权码后点击确定")
  stext(b.UAButton_Confirm,"确定")
  if b.UAPanel then
    hide(b.UAPanel.UAPanelCloseUAButton); hide(b.UAPanel.UAPanelCloseBtn); hide(b.UAPanel.UAPanelHomeBtn)
  end
  for _,n in ipairs({"BtnClose","CloseBtn","Button_Close","UAButton_Close","Btn_Back","Button_Back","BackBtn"}) do hide(b[n]) end
end

local function patch_panel()
  local P=sr("UAGame.Modules.ReNameCardModule.Panel.DefaultRenamePop.DefaultRenamePopPanel")
  if not P or P._ct then return P~=nil end
  P._ct=true
  local oCon=P._OnClickConfirm
  local oClose=P.CloseSelf
  function P:_OnClickConfirm(...)
    if self._login then
      local k=""
      if self.bind and self.bind.InputTextBox and self.bind.InputTextBox.GetText then
        local ok,v=pcall(self.bind.InputTextBox.GetText,self.bind.InputTextBox)
        if ok then k=trim(v):lower() end
      end
      if k==VK then
        R.ok=true; R.allow=true
        save_k(k)
        tip("授权成功，欢迎使用CT！",3)
        pcall(self.CloseSelf,self)
        start_product()
        return
      else
        tip("授权码错误，请重试",3); return
      end
    end
    if oCon then return oCon(self,...) end
  end
  local function blocked(s) return s and s._login and not R.ok and not R.allow end
  function P:CloseSelf(...) if blocked(self) then return end if oClose then return oClose(self,...) end end
  return true
end

local function open_login()
  if R.ok or R.panel then return end
  if not patch_panel() then tip("授权面板加载失败",3) return end
  local CT=sr("UAGame.CommandType")
  local PT=sr("UAGame.Services.PanelManager.PanelTypeDef")
  if not (UABoot and CT and PT and PT.DefaultRename) then tip("授权面板加载失败",3) return end
  pcall(function() UABoot:Call(CT.OpenPanelCommand,PT.DefaultRename,{_login=true}) end)
end

local function main()
  if R.done then return end
  R.done=true
  if load_k()==VK then
    R.ok=true
    tip("CT已授权，欢迎回来！",2)
    start_product()
    return
  end
  open_login()
end

-- 关键：加载时只注册延迟定时器，其他什么都不做（不卡启动）
if _G.TimerSys then
  pcall(function()
    _G.TimerSys:RegistedTimer("ct_boot",function() pcall(main) end,8.0,1)
  end)
end
