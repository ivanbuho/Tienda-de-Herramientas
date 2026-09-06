require "import"
import "android.os.Handler"
import "android.os.Looper"
import "android.content.Context"
import "android.speech.tts.TextToSpeech"
import "java.io.File"
import "android.os.Environment"
import "java.util.HashMap"
import "java.lang.Thread"
import "java.lang.Runnable"
import "java.net.URL"
import "java.net.HttpURLConnection"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "android.util.Base64"
import "java.lang.String"

-- ===================================================================
-- COMMENTIK FLASH - ACCESO DIRECTO (LECTOR EN VIVO)
-- Versión: 1.7
-- Desarrollo: Iván Búho | Comunidad: Crónicas Accesibles
-- Marca de Agua: CommenTik Flash
-- ===================================================================

local URL_MAESTRA = "https://www.dropbox.com/scl/fi/ygudhpngjoed4u9hjisv7/id_maestro.txt?rlkey=h5szrxlxjgl9gqsb4ms9yt208&st=xmrljn8g&dl=1"

local function obtenerRutaConfig()
    local root = Environment.getExternalStorageDirectory().getAbsolutePath()
    local dir = File(root .. "/accesibilidad con ivanbuho/CommenTik Flash")
    if not dir.exists() then pcall(function() dir.mkdirs() end) end
    return dir.getAbsolutePath() .. "/config.txt"
end

local function cargarConfiguracion()
    local cfg = { 
        PLANTILLA = "{usuario} dice: {comentario}", 
        MAX_COLA = 10, 
        TIEMPO_BASE = 2000, 
        TTS = "default",
        FILTRO_REPETICION = "false",
        LISTA_NEGRA = "",
        TTS_VEL = 1.0,
        TTS_VOL = 1.0,
        ANUNCIAR_SEGUIDORES = "false",
        ANUNCIAR_REGALOS = "false",
        ANUNCIAR_UNIONES = "false",
        ANUNCIAR_COMPARTIDAS = "false"
    }
    pcall(function()
        local f = io.open(obtenerRutaConfig(), "r")
        if f then
            for line in f:lines() do
                local k, v = line:match("^([^=]+)=(.*)$")
                if k and v then
                    k, v = k:match("^%s*(.-)%s*$"), v:match("^%s*(.-)%s*$")
                    if k == "MAX_COLA" or k == "TIEMPO_BASE" then cfg[k] = tonumber(v) or cfg[k]
                    elseif k == "TTS_VEL" or k == "TTS_VOL" then cfg[k] = tonumber(v) or cfg[k]
                    else cfg[k] = v end
                end
            end
            f:close()
        end
    end)
    return cfg
end

local function obtenerIDsPredeterminados()
    return {
        comentarios = {"com.zhiliaoapp.musically:id/f15", "com.zhiliaoapp.musically:id/f16"},
        nombres = {"com.zhiliaoapp.musically:id/pj3", "com.zhiliaoapp.musically:id/pj4"},
        eventos = {"com.zhiliaoapp.musically:id/text", "com.zhiliaoapp.musically:id/system_text"}
    }
end

local function decodificarBase64(str)
    local dec = nil
    pcall(function()
        local bytes = Base64.decode(str, Base64.DEFAULT)
        if bytes then dec = tostring(String(bytes, "UTF-8")) end
    end)
    return dec or str
end

local function parsearIDs(texto)
    local ids = { comentarios = {}, nombres = {}, eventos = {} }
    if not texto or texto == "" then return ids end

    local textoProbable = decodificarBase64(texto)
    if textoProbable and (textoProbable:find("ID") or textoProbable:find("com.zhiliaoapp")) then
        texto = textoProbable
    end

    for line in texto:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:find("^#") and line ~= "---" then
            if line:find("ID Usuario:") or line:find("^N:") then
                local val = line:match("ID Usuario:%s*(.+)") or line:match("^N:%s*(.+)")
                if val then table.insert(ids.nombres, val:match("^%s*(.-)%s*$")) end
            elseif line:find("ID Comentarios:") or line:find("^C:") then
                local val = line:match("ID Comentarios:%s*(.+)") or line:match("^C:%s*(.+)")
                if val then table.insert(ids.comentarios, val:match("^%s*(.-)%s*$")) end
            elseif line:find("ID Eventos:") or line:find("^E:") then
                local val = line:match("ID Eventos:%s*(.+)") or line:match("^E:%s*(.+)")
                if val then table.insert(ids.eventos, val:match("^%s*(.-)%s*$")) end
            end
        end
    end

    if #ids.comentarios == 0 and #ids.nombres == 0 and #ids.eventos == 0 then
        return obtenerIDsPredeterminados()
    end

    return ids
end

local function sincronizarIDsSilencioso()
    local ids = nil
    pcall(function()
        local url = URL(URL_MAESTRA)
        local conn = url.openConnection()
        conn.setConnectTimeout(2500)
        conn.setReadTimeout(2500)
        conn.setRequestMethod("GET")
        conn.setInstanceFollowRedirects(true)
        
        local is = conn.getInputStream()
        local reader = BufferedReader(InputStreamReader(is, "UTF-8"))
        local sb = {}
        local line = reader.readLine()
        while line ~= nil do
            table.insert(sb, tostring(line))
            line = reader.readLine()
        end
        reader.close()
        is.close()
        
        local txtCompleto = table.concat(sb, "\n")
        ids = parsearIDs(txtCompleto)
    end)
    
    if not ids or (#ids.comentarios == 0 and #ids.nombres == 0 and #ids.eventos == 0) then
        ids = obtenerIDsPredeterminados()
    end
    return ids
end

local function cargarIDsRemotosAsync(alFinalizar)
    Thread(Runnable({
        run = function()
            local ids = sincronizarIDsSilencioso()
            _G.TikTok_IDs = ids
            if alFinalizar then
                pcall(function() alFinalizar() end)
            end
        end
    })).start()
end

if _G.TikTokMonitoreando == nil then _G.TikTokMonitoreando = false end
if not _G.TikTokHandler then _G.TikTokHandler = Handler(Looper.getMainLooper()) end

local function vibrar()
    pcall(function()
        local ctx = service or activity
        if ctx then
            local v = ctx.getSystemService(Context.VIBRATION_SERVICE)
            if v then v.vibrate(25) end
        end
    end)
end

local function hablar(texto)
    pcall(function()
        if _G.CommenTikTTS and _G.CommenTikTTS_Listo then
            local vol = _G.TikTok_Cfg and _G.TikTok_Cfg.TTS_VOL or 1.0
            local params = HashMap()
            params.put("volume", tostring(vol))
            _G.CommenTikTTS.speak(texto, TextToSpeech.QUEUE_ADD, params)
        elseif service then
            if service.speak then service.speak(texto)
            elseif service.postExecute then service.postExecute(texto) end
        end
    end)
end

local function inicializarTTSSecundario(paqueteEngine, velocidad, volumen, alConcluir)
    local ctx = service or activity
    if not ctx then return end
    pcall(function()
        if _G.CommenTikTTS then _G.CommenTikTTS.stop(); _G.CommenTikTTS.shutdown(); _G.CommenTikTTS = nil end
    end)
    if paqueteEngine and paqueteEngine ~= "default" then
        pcall(function()
            local listener = luajava.createProxy("android.speech.tts.TextToSpeech$OnInitListener", {
                onInit = function(status) 
                    if status == TextToSpeech.SUCCESS then 
                        _G.CommenTikTTS_Listo = true 
                        pcall(function() _G.CommenTikTTS.setSpeechRate(velocidad) end)
                    end 
                end
            })
            _G.CommenTikTTS = TextToSpeech(ctx, listener, paqueteEngine)
        end)
    else
        _G.CommenTikTTS_Listo = false
    end
    if alConcluir then alConcluir() end
end

local function procesarCola()
    if not _G.TikTokMonitoreando then return end
    if _G.ColaComentarios and #_G.ColaComentarios > 0 then
        local max = _G.TikTok_Cfg.MAX_COLA or 10
        while #_G.ColaComentarios > max do table.remove(_G.ColaComentarios, 1) end

        local msg = table.remove(_G.ColaComentarios, 1)
        hablar(msg)

        local factor, base = 75, _G.TikTok_Cfg.TIEMPO_BASE or 2000
        if #_G.ColaComentarios > 3 then factor, base = math.floor(factor * 0.8), math.floor(base * 0.8) end
        
        local espera = math.max(1500, (#msg * factor) + base)
        _G.TikTokHandler.postDelayed(luajava.createProxy("java.lang.Runnable", { run = function() procesarCola() end }), espera)
    else
        _G.TikTokHandler.postDelayed(luajava.createProxy("java.lang.Runnable", { run = function() procesarCola() end }), 500)
    end
end

local function contienePalabraProhibida(mensaje, listaNegra)
    if not listaNegra or listaNegra == "" then return false end
    local msgLower = mensaje:lower()
    for palabra in string.gmatch(listaNegra, "([^,]+)") do
        palabra = palabra:match("^%s*(.-)%s*$")
        if palabra ~= "" and msgLower:find(palabra:lower(), 1, true) then return true end
    end
    return false
end

local function aplicarFiltroRepeticion(texto)
    if not _G.TikTok_Cfg or _G.TikTok_Cfg.FILTRO_REPETICION ~= "true" then return texto end
    local res = texto
    pcall(function()
        res = res:gsub("(%S+)%s+%1%s+%1%s+(%1%s*)+", "%1 %1 %1 ")
        res = res:gsub("(%S)%1%1%1+", "%1%1%1")
    end)
    return res
end

local function obtenerNombreUsuario(nodoPadre)
    if not nodoPadre then return "Alguien" end
    local res = "Alguien"
    pcall(function()
        if _G.TikTok_IDs and _G.TikTok_IDs.nombres then
            for _, idN in ipairs(_G.TikTok_IDs.nombres) do
                local nodos = nodoPadre.findAccessibilityNodeInfosByViewId(idN)
                if nodos and not nodos.isEmpty() then
                    local n = nodos.get(0)
                    if n then
                        local txt = n.getText()
                        if txt and tostring(txt) ~= "" then 
                            res = tostring(txt) 
                            pcall(function() n.recycle() end)
                            break 
                        end
                        pcall(function() n.recycle() end)
                    end
                end
            end
        end
    end)
    return res
end

local function procesarNodoComentario(nodoItem)
    if not nodoItem or not _G.TikTokMonitoreando then return end
    pcall(function()
        local txt = nodoItem.getText()
        if not txt then return end
        local msg = tostring(txt)
        if #msg > 0 then
            if contienePalabraProhibida(msg, _G.TikTok_Cfg.LISTA_NEGRA) then return end
            msg = aplicarFiltroRepeticion(msg)
            
            if not _G.comentarios_leidos then _G.comentarios_leidos = {} end
            if _G.comentarios_leidos[msg] then return end
            
            local padre = nodoItem.getParent()
            local usuario = "Alguien"
            if padre then 
                usuario = obtenerNombreUsuario(padre)
                pcall(function() padre.recycle() end) 
            end
            
            local plantilla = _G.TikTok_Cfg.PLANTILLA or "{usuario} dice: {comentario}"
            local frase = plantilla:gsub("{usuario}", usuario):gsub("{comentario}", msg)
            
            _G.comentarios_leidos[msg] = true
            table.insert(_G.ColaComentarios, frase)
            _G.TikTokHuboActividad = true 
        end
    end)
end

local function procesarNodoEvento(nodoItem)
    if not nodoItem or not _G.TikTokMonitoreando then return end
    pcall(function()
        local txt = nodoItem.getText()
        if not txt then return end
        local msg = tostring(txt)
        if #msg > 0 then
            if contienePalabraProhibida(msg, _G.TikTok_Cfg.LISTA_NEGRA) then return end
            
            local msgLower = msg:lower()
            local esSeguidor = msgLower:find("sigue al creador") or msgLower:find("comenzó a seguir") or msgLower:find("started following") or msgLower:find("te sigue") or msgLower:find("seguiu")
            local esRegalo = msgLower:find("envió") or msgLower:find("sent") or msgLower:find("regalo") or msgLower:find("enviou")
            local esUnion = msgLower:find("se unió") or msgLower:find("joined") or msgLower:find("entrou")
            local esCompartida = msgLower:find("compartió") or msgLower:find("shared") or msgLower:find("compartilhou")
            
            local estaPermitido = false
            if esSeguidor and _G.TikTok_Cfg.ANUNCIAR_SEGUIDORES == "true" then estaPermitido = true
            elseif esRegalo and _G.TikTok_Cfg.ANUNCIAR_REGALOS == "true" then estaPermitido = true
            elseif esUnion and _G.TikTok_Cfg.ANUNCIAR_UNIONES == "true" then estaPermitido = true
            elseif esCompartida and _G.TikTok_Cfg.ANUNCIAR_COMPARTIDAS == "true" then estaPermitido = true
            end
            
            if not estaPermitido then return end
            
            if not _G.comentarios_leidos then _G.comentarios_leidos = {} end
            if _G.comentarios_leidos[msg] then return end
            
            _G.comentarios_leidos[msg] = true
            table.insert(_G.ColaComentarios, msg)
            _G.TikTokHuboActividad = true 
        end
    end)
end

local function hacerBarridoInicialInteligente()
    pcall(function()
        local rootNode = service.getRootInActiveWindow()
        if not rootNode then return end
        
        local listaTemp = {}
        
        if _G.TikTok_IDs and _G.TikTok_IDs.comentarios then
            for _, idC in ipairs(_G.TikTok_IDs.comentarios) do
                local nodosC = rootNode.findAccessibilityNodeInfosByViewId(idC)
                if nodosC and not nodosC.isEmpty() then
                    for i = 0, nodosC.size() - 1 do
                        local n = nodosC.get(i)
                        if n then
                            local txt = n.getText()
                            if txt and tostring(txt) ~= "" then
                                table.insert(listaTemp, { nodo = n, texto = tostring(txt), tipo = "comentario" })
                            else
                                pcall(function() n.recycle() end)
                            end
                        end
                    end
                end
            end
        end
        
        if _G.TikTok_IDs and _G.TikTok_IDs.eventos then
            for _, idE in ipairs(_G.TikTok_IDs.eventos) do
                local nodosE = rootNode.findAccessibilityNodeInfosByViewId(idE)
                if nodosE and not nodosE.isEmpty() then
                    for i = 0, nodosE.size() - 1 do
                        local n = nodosE.get(i)
                        if n then
                            local txt = n.getText()
                            if txt and tostring(txt) ~= "" then
                                table.insert(listaTemp, { nodo = n, texto = tostring(txt), tipo = "evento" })
                            else
                                pcall(function() n.recycle() end)
                            end
                        end
                    end
                end
            end
        end
        
        local count = #listaTemp
        if count > 0 then
            for idx = 1, count - 1 do
                _G.comentarios_leidos[listaTemp[idx].texto] = true
                pcall(function() listaTemp[idx].nodo.recycle() end)
            end
            local ultimo = listaTemp[count]
            if ultimo.tipo == "comentario" then
                procesarNodoComentario(ultimo.nodo)
            else
                procesarNodoEvento(ultimo.nodo)
            end
            pcall(function() ultimo.nodo.recycle() end)
        end
        
        pcall(function() rootNode.recycle() end)
    end)
end

local function escanearChatPreciso()
    if not _G.TikTokMonitoreando then return end
    _G.TikTokHuboActividad = false
    
    pcall(function()
        local rootNode = service.getRootInActiveWindow()
        if not rootNode then return end
        
        if _G.TikTok_IDs and _G.TikTok_IDs.comentarios then
            for _, idC in ipairs(_G.TikTok_IDs.comentarios) do
                local nodosC = rootNode.findAccessibilityNodeInfosByViewId(idC)
                if nodosC and not nodosC.isEmpty() then
                    for i = 0, nodosC.size() - 1 do
                        local n = nodosC.get(i)
                        if n then procesarNodoComentario(n); pcall(function() n.recycle() end) end
                    end
                end
            end
        end
        
        if _G.TikTok_IDs and _G.TikTok_IDs.eventos then
            for _, idE in ipairs(_G.TikTok_IDs.eventos) do
                local nodosE = rootNode.findAccessibilityNodeInfosByViewId(idE)
                if nodosE and not nodosE.isEmpty() then
                    for i = 0, nodosE.size() - 1 do
                        local n = nodosE.get(i)
                        if n then procesarNodoEvento(n); pcall(function() n.recycle() end) end
                    end
                end
            end
        end
        
        pcall(function() rootNode.recycle() end)
    end)

    if _G.TikTokHuboActividad then 
        _G.TikTokCiclosInactivos = 0
    else 
        _G.TikTokCiclosInactivos = (_G.TikTokCiclosInactivos or 0) + 1 
    end

    local tiempoSiguiente = 1000
    if _G.TikTokCiclosInactivos > 20 then 
        tiempoSiguiente = 3500
    elseif _G.TikTokCiclosInactivos > 5 then 
        tiempoSiguiente = 2000
    end

    _G.TikTokHandler.postDelayed(luajava.createProxy("java.lang.Runnable", { run = function() escanearChatPreciso() end }), tiempoSiguiente)
end

vibrar()

if _G.TikTokMonitoreando then
    -- DESACTIVACIÓN Y LIMPIEZA ABSOLUTA DE RECURSOS (RAM Y BATERÍA)
    _G.TikTokMonitoreando = false
    pcall(function() _G.TikTokHandler.removeCallbacksAndMessages(nil) end)
    pcall(function() if _G.CommenTikTTS then _G.CommenTikTTS.stop(); _G.CommenTikTTS.shutdown(); _G.CommenTikTTS = nil end end)
    _G.CommenTikTTS_Listo = nil
    _G.comentarios_leidos = nil
    _G.ColaComentarios = nil
    _G.TikTokCiclosInactivos = nil
    _G.TikTokHuboActividad = nil
    _G.TikTok_Cfg = nil
    _G.TikTok_IDs = nil
    collectgarbage("collect")
    hablar("Desactivado por Iván Búho")
else
    -- ACTIVACIÓN E INICIALIZACIÓN SINCRONIZADA Y SILENCIOSA
    _G.TikTokMonitoreando = true
    _G.TikTok_Cfg = cargarConfiguracion()
    _G.comentarios_leidos = {}
    _G.ColaComentarios = {}
    _G.TikTokCiclosInactivos = 0

    inicializarTTSSecundario(_G.TikTok_Cfg.TTS, _G.TikTok_Cfg.TTS_VEL, _G.TikTok_Cfg.TTS_VOL, function()
        hablar("Activado por Iván Búho")
        
        cargarIDsRemotosAsync(function()
            hacerBarridoInicialInteligente()
            _G.TikTokHandler.postDelayed(luajava.createProxy("java.lang.Runnable", {
                run = function() if _G.TikTokMonitoreando then escanearChatPreciso(); procesarCola() end end
            }), 1500)
        end)
    end)
end