-- 串腾授权内置版 v1
local RUNTIME_KEY = "__CHUANTENG_AUTH"
local R = rawget(_G, RUNTIME_KEY) or {}
rawset(_G, RUNTIME_KEY, R)
R.auth_started = false
R.auth_ok = R.auth_ok == true
R.login_busy = false
R.login_panel = nil
R.allow_close = false

-- 内置卡密
local VALID_KEY = "CTNB886446"
-- 本地存储路径
local SAVE_FILE = "/storage/emulated/0/Android/data/com.tencent.mf.uam/files/ct.txt"

local function trim(s) return tostring(s or ""):gsub("^%s+",""):gsub("%s+$","") end
local function upper(s) return trim(s):upper() end
local function safe_require(n) local ok,r=pcall(require,n) if ok then return r end return nil end
local function widget_call(w,m,...) if w and type(w[m])=="function" then local ok=pcall(w[m],w,...) return ok end return false end
local function set_text(w,t)
  if not w then return false end
  for _,m in ipairs({"SetText","SetContentText","SetTitleText","SetHintText","SetButtonText"}) do
    if widget_call(w,m,t) then return true end
  end
  return false
end
local function hide_widget(w)
  if not w then return end
  widget_call(w,"SetIsEnabled",false)
  widget_call(w,"SetRenderOpacity",0)
  if UE4 and UE4.ESlateVisibility and w.SetVisibility then
    pcall(w.SetVisibility,w,UE4.ESlateVisibility.Collapsed)
  end
end
local function show_tip(text,dur)
  if UABoot and UABoot.TipManager and type(UABoot.TipManager.Toast)=="function" then
    pcall(UABoot.TipManager.Toast,UABoot.TipManager,{content=tostring(text or ""),duration=dur or 2})
  end
end

-- 读本地卡密
local function load_saved_key()
  if UE4 and UE4.UBFLPlatformFile and type(UE4.UBFLPlatformFile.LoadFileToString)=="function" then
    local ok,data = pcall(UE4.UBFLPlatformFile.LoadFileToString,SAVE_FILE)
    if ok and type(data)=="string" and #data > 0 then
      return trim(data)
    end
  end
  local f = io and io.open and io.open(SAVE_FILE,"rb")
  if f then
    local data = f:read("*a") or ""
    f:close()
    return trim(data)
  end
  return ""
end

-- 保存卡密
local function save_key(key)
  key = trim(key)
  if UE4 and UE4.UBFLPlatformFile and type(UE4.UBFLPlatformFile.SaveStringToFile)=="function" then
    pcall(UE4.UBFLPlatformFile.SaveStringToFile, key, SAVE_FILE)
    return
  end
  local f = io and io.open and io.open(SAVE_FILE,"wb")
  if f then
    f:write(key)
    f:close()
  end
end

local function configure_login_panel(panel)
  if not panel or not panel.bind then return end
  R.login_panel = panel
  local b = panel.bind
  if b.InputTextBox then
    widget_call(b.InputTextBox,"SetText","")
    widget_call(b.InputTextBox,"SetHintText","请输入授权码")
  end
  set_text(b.TitleText or b.Text_Title or b.Txt_Title,"串腾授权验证")
  set_text(b.ContentText or b.Text_Content or b.TxtContent,"欢迎使用串腾，请输入授权码后点击确定")
  set_text(b.UAButton_Confirm,"确定")
  if b.UAPanel then
    hide_widget(b.UAPanel.UAPanelCloseUAButton)
    hide_widget(b.UAPanel.UAPanelCloseBtn)
    hide_widget(b.UAPanel.UAPanelHomeBtn)
  end
  for _,n in ipairs({"BtnClose","CloseBtn","Button_Close","UAButton_Close","Btn_Back","Button_Back","BackBtn"}) do
    hide_widget(b[n])
  end
end

local function patch_login_panel()
  local P = safe_require("UAGame.Modules.ReNameCardModule.Panel.DefaultRenamePop.DefaultRenamePopPanel")
  if not P or P.__ct_patched then return P ~= nil end
  P.__ct_patched = true
  P.__ct_oPre = P.OnPreOpen
  P.__ct_oCon = P._OnClickConfirm
  P.__ct_oClose = P.CloseSelf
  P.__ct_oGoBack = P.OnGoBack
  P.__ct_oClickClose = P.OnClickClose
  P.__ct_oClickUAClose = P.OnClickUAPanelClose
  P.__ct_oOnClose = P.OnClose

  function P:OnPreOpen(args)
    local ret = P.__ct_oPre(self,args)
    if type(args)=="table" and args.__ct_login==true then
      self.__ct_login = true
      configure_login_panel(self)
    end
    return ret
  end

  function P:_OnClickConfirm(...)
    if self.__ct_login then
      if R.login_busy then show_tip("验证中...",2) return end
      local key = ""
      if self.bind and self.bind.InputTextBox and type(self.bind.InputTextBox.GetText)=="function" then
        local ok,v = pcall(self.bind.InputTextBox.GetText,self.bind.InputTextBox)
        if ok then key = upper(v) end
      end
      if key == VALID_KEY then
        R.auth_ok = true
        R.allow_close = true
        save_key(key)
        show_tip("授权成功，欢迎使用串腾！",3)
        pcall(self.CloseSelf,self)
        return
      else
        show_tip("授权码错误，请重试",3)
        return
      end
    end
    if P.__ct_oCon then return P.__ct_oCon(self,...) end
  end

  local function block_close(self)
    return self and self.__ct_login==true and not R.auth_ok and not R.allow_close
  end

  function P:OnGoBack(...)
    if block_close(self) then return true end
    if P.__ct_oGoBack then return P.__ct_oGoBack(self,...) end
    return false
  end
  function P:OnClickClose(...)
    if block_close(self) then return end
    if P.__ct_oClickClose then return P.__ct_oClickClose(self,...) end
  end
  function P:OnClickUAPanelClose(...)
    if block_close(self) then return end
    if P.__ct_oClickUAClose then return P.__ct_oClickUAClose(self,...) end
  end
  function P:CloseSelf(...)
    if block_close(self) then return end
    if P.__ct_oClose then return P.__ct_oClose(self,...) end
  end
  function P:OnClose(...)
    local was = self.__ct_login==true
    local ret = P.__ct_oOnClose(self,...)
    if was then
      R.login_panel = nil
      if not R.auth_ok and not R.allow_close then
        if _G.TimerSys then
          pcall(function()
            _G.TimerSys:RegistedTimer("ct_reopen",function() R.open_login() end,0.2,1)
          end)
        end
      end
    end
    return ret
  end
  return true
end

function R.open_login()
  if R.auth_ok then return end
  if R.login_panel then return end
  if not patch_login_panel() then
    show_tip("授权面板加载失败",3)
    return
  end
  local CT = safe_require("UAGame.CommandType")
  local PT = safe_require("UAGame.Services.PanelManager.PanelTypeDef")
  if not (UABoot and CT and PT and PT.DefaultRename) then
    show_tip("授权面板加载失败",3)
    return
  end
  local ok = pcall(function()
    UABoot:Call(CT.OpenPanelCommand,PT.DefaultRename,{__ct_login=true})
  end)
  if not ok then show_tip("授权面板打开失败",3) end
end

local function main_ui_present()
  local PT = safe_require("UAGame.Services.PanelManager.PanelTypeDef")
  if UABoot and UABoot.PanelManager and PT and type(UABoot.PanelManager.GetPanel)=="function" then
    local ok,p = pcall(UABoot.PanelManager.GetPanel,UABoot.PanelManager,PT.MainUI)
    return ok and p ~= nil
  end
  return false
end

local function start_auth()
  if R.auth_started or R.auth_ok then return end
  R.auth_started = true
  -- 先检查本地有没有保存的卡密
  local saved = load_saved_key()
  if saved == VALID_KEY then
    R.auth_ok = true
    show_tip("串腾已授权，欢迎回来！",2)
    return
  end
  -- 没有就弹窗
  R.open_login()
end

local function on_lobby_ready()
  if R.auth_started or R.auth_ok then return end
  start_auth()
end

local function patch_main_ui()
  local M = safe_require("UAGame.Modules.MainUIModule.Panel.MainUI.MainUIPanel")
  if not M or M.__ct_hooked then return M ~= nil end
  M.__ct_hooked = true
  for _,m in ipairs({"OnOpen","OnShow","OnOpenAnimationEnd","OnLoadingComplete"}) do
    if type(M[m])=="function" then
      local orig = M[m]
      M[m] = function(self,...)
        local ret = orig(self,...)
        on_lobby_ready()
        return ret
      end
    end
  end
  return true
end

local function start_watchdog()
  if not _G.TimerSys then
    if main_ui_present() then on_lobby_ready() end
    return
  end
  local ticks = 0
  pcall(function()
    _G.TimerSys:RegistedRepeatTimeTimer("ct_watchdog",R,function()
      ticks = ticks + 1
      if main_ui_present() then
        on_lobby_ready()
      elseif ticks >= 70 then
        -- 70秒兜底
      end
    end,0,1,70)
  end)
end

-- 启动
patch_main_ui()
if main_ui_present() then
  on_lobby_ready()
else
  start_watchdog()
end
