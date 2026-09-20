--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Network = {}

-- Função de validação registrada com SetValidator.
-- Retorna true/false e, opcionalmente o motivo da falha.

export type Validator = (player: Player, ...any) -> (boolean, string?)

-- Objeto retornado por OnServerEvent

export type ServerEvent = {
	Connect: (self: ServerEvent, callback: (player: Player, ...any) -> ()) -> RBXScriptConnection,
	Once: (self: ServerEvent, callback: (player: Player, ...any) -> ()) -> RBXScriptConnection,
	Wait: (self: ServerEvent) -> (Player, ...any),
}

-- Configuração aceita por Network.Prewarm (todos os campos são opcionais)

export type PrewarmConfig = {
	remoteEvents: { string }?,
	remoteFunctions: { string }?,
	bindableEvents: { string }?,
	bindableFunctions: { string }?,
}

-- Retorno de Network.GetEventList

export type EventList = {
	RemoteEvents: { string },
	RemoteFunctions: { string },
	BindableEvents: { string },
	BindableFunctions: { string },
}

------------------------------------------------------------------------------------------------------------------------------------------------------------------

local CONFIG = {

	-- Prefixos para cada tipo de evento

	PREFIX_REMOTE_EVENT = "rev_",
	PREFIX_REMOTE_FUNCTION = "rfn_",
	PREFIX_BINDABLE_EVENT = "bev_",
	PREFIX_BINDABLE_FUNCTION = "bfn_",

	-- Timeout para o WaitForChild do cliente

	WAIT_TIMEOUT = 10,

	-- Se TRUE vai imprimir os logs de debug

	DEBUG = false,
}

-------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Eventos únicos do servidor (Para bindableEvents)

-- Eventos únicos do servidor (Para bindableEvents)

local SERVER_ONLY_EVENTS: { [string]: boolean } = {
	exemplo = true,
	TestServerEvent = true,
}

-- Mesma ideia, mas para bindableFunctions

local SERVER_ONLY_FUNCTIONS: { [string]: boolean } = {}

--------------------------------------------------------------------------------------------------------------------------------------

-- Tabelas de cache separadas por tipo

local cache = {

	RemoteEvents: { [string]: RemoteEvent },
	RemoteFunctions: { [string]: RemoteFunction },
	BindableEvents: { [string]: BindableEvent },
	BindableFunctions: { [string]: BindableFunction },	

} = {

	RemoteEvents = {},
	RemoteFunctions = {},
	BindableEvents = {},
	BindableFunctions = {},
}

-- Validadores registrados para RemoteEvents

local Validators: { [string]: Validator } = {}

---------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Funções utilitárias internas

local function DebugPrint(...: any)
	if CONFIG.DEBUG then
		print("[Network]", ...)
	end
end

-- Verifica se está rodando no cliente ou servidor

local IS_CLIENT = RunService:IsClient()

local IS_SERVER = RunService:IsServer()

---------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Parte importante bebê

-- Obtenção de eventos + cache e criação autmática + Profissionalismo Mourant

local function _getRemoteEvent(name: string): RemoteEvent
	-- verifica cache primeiro
	local cached = cache.RemoteEvents[name]
	if cached then
		return cached
	end

	local RealName = CONFIG.PREFIX_REMOTE_EVENT .. name

	local Existing = script:FindFirstChild(RealName)

	if Existing then
		-- Proteção pra ter certeza que é um RemoteEvent
		if not Existing:IsA("RemoteEvent") then
			error(
				string.format(

					'[Network] Objeto "%s" já existe no módulo, mas não é um RemoteEvent (é %s). '
						.. "Verifique se não há conflito de nomes com outro tipo de instância.",
					RealName,
					Existing.ClassName
				)
			)
		end

		cache.RemoteEvents[name] = Existing :: RemoteEvent
		return Existing :: RemoteEvent
	end

	if IS_CLIENT then
		-- Aqui  o cliente deve esperar o servidor criar
		DebugPrint("Cliente aguardando RemoteEvent:", RealName)

		local event = script:WaitForChild(RealName, CONFIG.WAIT_TIMEOUT)

		if not event then
			error(
				string.format(
					"[Network] Timeout: RemoteEvent '%s' não foi criado pelo servidor em %d segundos. "
						.. "Verifique se o servidor registrou esse evento antes do cliente tentar usá-lo.",
					name,
					CONFIG.WAIT_TIMEOUT
				)
			)
		end

		-- Verificação de tipo igual o primeiro
		if not event:IsA("RemoteEvent") then
			error(
				string.format(
					'[Network] Objeto "%s" foi encontrado, mas não é um RemoteEvent (é %s).',
					RealName,
					event.ClassName
				)
			)
		end

		cache.RemoteEvents[name] = event :: RemoteEvent
		return event :: RemoteEvent
	else
		-- Servidor cria o evento

		DebugPrint("Servidor criando RemoteEvent:", RealName)

		local event = Instance.new("RemoteEvent")
		event.Name = RealName
		event.Parent = script

		cache.RemoteEvents[name] = event
		return event
	end
end
-----------------------------------------------------------------------------------------------------------------------------------------

-- Busca ou cria um RemoteFunction, essa lógica vai se reptir bastante

local function _getRemoteFunction(name: string): RemoteFunction
	local cached = cache.RemoteFunctions[name]
	if cached then
		return cached
	end

	local RealName = CONFIG.PREFIX_REMOTE_FUNCTION .. name

	local Existing = script:FindFirstChild(RealName)

	if Existing then
		if not Existing:IsA("RemoteFunction") then
			error(
				string.format(
					'[Network] Objeto "%s" já existe no módulo, mas não é um RemoteFunction (é %s). '
						.. "Verifique se não há conflito de nomes com outro tipo de instância.",
					RealName,
					Existing.ClassName
				)
			)
		end

		cache.RemoteFunctions[name] = Existing :: RemoteFunction
		return Existing :: RemoteFunction
	end

	if IS_CLIENT then
		DebugPrint("Cliente aguardando RemoteFunction", RealName)
		local func = script:WaitForChild(RealName, CONFIG.WAIT_TIMEOUT)

		if not func then
			error(
				string.format(
					"[Network] Timeout: RemoteFunction '%s' não foi criado pelo servidor em %d segundos.",
					name,
					CONFIG.WAIT_TIMEOUT
				)
			)
		end

		if not func:IsA("RemoteFunction") then
			error(
				string.format(
					'[Network] Objeto "%s" foi encontrado, mas não é um RemoteFunction (é %s).',
					RealName,
					func.ClassName
				)
			)
		end

		cache.RemoteFunctions[name] = func :: RemoteFunction
		return func :: RemoteFunction
	else
		DebugPrint("Servidor criando RemoteFunction:", RealName)
		local func = Instance.new("RemoteFunction")
		func.Name = RealName
		func.Parent = script

		cache.RemoteFunctions[name] = func
		return func
	end
end

-------------------------------------------------------------------------------------------------------------------------------------

-- BindableEvents, como eu disse isso só vai se repetir. Meu medo é eu esquecer algo em um.

local function _getBindableEvent(name: string): BindableEvent
	if SERVER_ONLY_EVENTS[name] and not IS_SERVER then
		error(string.format('[Network] BindableEvent "%s" é exclusivo do servidor e foi solicitado no cliente.', name))
	end

	local cached = cache.BindableEvents[name]
	if cached then
		return cached
	end

	local RealName = CONFIG.PREFIX_BINDABLE_EVENT .. name

	DebugPrint("Criando BindableEvent (local a este contexto):", RealName)
	local event = Instance.new("BindableEvent")
	event.Name = RealName

	cache.BindableEvents[name] = event
	return event
end
--------------------------------------------------------------------------------------------------------------------------------------------

-- BindableFunction — mesma lógica e mesmo motivo de não ter Parent (ver nota em _getBindableEvent).

local function _getBindableFunction(name: string): BindableFunction
	if SERVER_ONLY_FUNCTIONS[name] and not IS_SERVER then
		error(
			string.format('[Network] BindableFunction "%s" é exclusiva do servidor e foi solicitada no cliente.', name)
		)
	end

	local cached = cache.BindableFunctions[name]
	if cached then
		return cached
	end

	local RealName = CONFIG.PREFIX_BINDABLE_FUNCTION .. name

	DebugPrint("Criando BindableFunction (local a este contexto):", RealName)
	local func = Instance.new("BindableFunction")
	func.Name = RealName
	-- Sem func.Parent = script — ver nota em _getBindableEvent.

	cache.BindableFunctions[name] = func
	return func
end
-----------------------------------------------------------------------------------------------------------------------------------

-- Sistema de validação, mesma ideia padrão, validar no servidor e não no cliente

-- Outra parte importante, o any em players serve para receber qualquer quantidade de argumentos

-- boolean retorna true e false enquanto string? significa que pode ser nil, ai é so para o motivo de falha na validação
-- (essa assinatura agora está no tipo exportado Validator, lá em cima)

function Network.SetValidator(EventName: string, Validator: Validator)
	if IS_CLIENT then
		warn("[Network] Validadores só devem ser registrados no servidor. Ignorando.")
		return
	end

	assert(type(EventName) == "string" and EventName ~= "", "[Network] EventName precisa ser uma string não vazia.")

	assert(type(Validator) == "function", "[Network] Validator precisa ser uma função.")

	Validators[EventName] = Validator
	DebugPrint("Validador registrado para:", EventName)
end

-- Remover Validator, bem explicatorio...

function Network.RemoveValidator(eventName: string)
	if IS_CLIENT then
		warn("[Network] Validadores só devem ser removidos no servidor. Ignorando.")
		return
	end

	Validators[eventName] = nil
	DebugPrint("Validador removido para:", eventName)
end

-- Adição do helper

local function _RunValidator(name: string, player: Player, ...: any): boolean
	local Validator = Validators[name]

	if not Validator then
		return true -- Pode ser válido mesmo sem um validador registrado
	end

	local success, ok, err = pcall(Validator, player, ...)

	if not success then
		warn(
			string.format(
				"[Network] Validador de '%s' gerou um erro ao processar evento de %s: %s",
				name,
				player.Name,
				tostring(ok)
			)
		)
		return false
	end

	if not ok then
		warn(
			string.format(
				"[Network] Validação falhou para '%s' de %s: %s",
				name,
				player.Name,
				err or "Motivo desconhecido"
			)
		)
		return false
	end

	return true
end
---------------------------------------------------------------------------------------------------------------------------------------------------------

-- RemoteEvents, Cliente e Servidor

function Network.FireServer(name: string, ...: any)
	if IS_SERVER then
		error("[Network] FireServer só pode ser chamado do cliente.")
	end

	local event = _getRemoteEvent(name)
	event:FireServer(...)
end

function Network.FireClient(name: string, client: Player, ...: any)
	if IS_CLIENT then
		error("[Network] FireClient só pode ser chamado do servidor.")
	end

	local event = _getRemoteEvent(name)
	event:FireClient(client, ...)
end

-- Dispara pra todo mundo conectado, massa

function Network.FireAllClients(name: string, ...: any)
	if IS_CLIENT then
		error("[Network] FireAllClients só pode ser chamado do servidor.")
	end

	local event = _getRemoteEvent(name)
	event:FireAllClients(...)
end

-- Dispara pra todos os clientes, menos um escolhido, se for preconceituoso...

function Network.FireExceptClient(name: string, exceptClient: Player, ...: any)
	if IS_CLIENT then
		error("[Network] FireExceptClient só pode ser chamado do servidor.")
	end

	local event = _getRemoteEvent(name)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= exceptClient then
			event:FireClient(player, ...)
		end
	end
end

-- Usado pelo cliente para ouvir eventos vindos do servidor.
-- RBXScriptSignal é usado pelo Roblox para representar sinais/eventos que você pode conectar com .Connect

function Network.OnClientEvent(name: string): RBXScriptSignal
	local event = _getRemoteEvent(name)
	return event.OnClientEvent
end

-- Usado pelo servidor para ouvir eventos vindos do cliente.
-- Se houver um validador registrado para esse evento, ele será executado
-- antes do callback. Se falhar, o callback não é chamado.

function Network.OnServerEvent(name: string): ServerEvent
	if IS_CLIENT then
		error("[Network] OnServerEvent só pode ser chamado do servidor.")
	end

	local event = _getRemoteEvent(name)

	return {
		-- Depois da seta indica o tipo de retorno da função, engraçado
		-- nesse caso () equivale a void, meros nada

		Connect = function(_: ServerEvent, callback: (player: Player, ...any) -> ())
			return event.OnServerEvent:Connect(function(player: Player, ...)
				if not _runValidator(name, player, ...) then
					return
				end

				-- Callback é só isso: uma função que você entrega como argumento pra outra função, em vez de chamar ela na hora.
				callback(player, ...)
			end)
		end,

		-- Once está sendo usado para conectar callbacks que só rodem uma vez.
		-- Só um evento VÁLIDO consome o Once: eventos inválidos são ignorados e ele continua esperando.

		Once = function(_: ServerEvent, callback: (player: Player, ...any) -> ())
			local connection: RBXScriptConnection

			connection = event.OnServerEvent:Connect(function(player: Player, ...)
				if not _runValidator(name, player, ...) then
					return
				end

				connection:Disconnect()
				callback(player, ...)
			end)

			return connection
		end,

		-- Aceita "_" (self) igual Connect/Once, mesmo sem usar — só por consistência de assinatura.
		-- Ignora eventos inválidos e continua esperando até chegar um válido.
		-- table.pack/args.n preservam argumentos nil no meio da lista.

		Wait = function(_: ServerEvent)
			while true do
				local args = table.pack(event.OnServerEvent:Wait())
				local player = args[1] :: Player

				if _runValidator(name, player, table.unpack(args, 2, args.n)) then
					return table.unpack(args, 1, args.n)
				end
			end
		end,
	}
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------

-- RemoteFunctions cliente para servidor

--O cliente invoca uma função do servidor e espera a resposta

function Network.InvokeServer(name: string, ...: any): ...any
	if IS_SERVER then
		error("[Network] InvokeServer só pode ser chamado do cliente.")
	end

	local func = _getRemoteFunction(name)
	return func:InvokeServer(...)
end

-- o Contrario, o servidor invoca uma função no cliente

function Network.InvokeClient(name: string, client: Player, ...: any): ...any
	if IS_CLIENT then
		error("[Network] InvokeClient só pode ser chamado do servidor.")
	end

	local func = _getRemoteFunction(name)
	return func:InvokeClient(client, ...)
end

function Network.OnServerInvoke(name: string, callback: (Player, ...any) -> ...any)
	if IS_CLIENT then
		error("[Network] OnServerInvoke só pode ser chamado do servidor.")
	end

	local func = _getRemoteFunction(name)
	func.OnServerInvoke = callback
end

-- o contrário, registra o callback que o cliente executa quando o servidor invoca

function Network.OnClientInvoke(name: string, callback: (...any) -> ...any)
	if IS_SERVER then
		error("[Network] OnClientInvoke só pode ser chamado do cliente.")
	end

	local func = _getRemoteFunction(name)
	func.OnClientInvoke = callback
end

-----------------------------------------------------------------------------------------------------------------------------------------------------

-- BindableEvents Mesmo contexto, chegaaaaaa.

-- Dispara um BindableEvent. Funciona apenas entre scripts do mesmo contexto
-- (mesmo VM — servidor OU cliente, nunca os dois).

function Network.FireBindable(name: string, ...: any)
	local event = _getBindableEvent(name)
	event:Fire(...)
end

-- Retorna o sinal Event de um BindableEvent.

function Network.OnBindableEvent(name: string): RBXScriptSignal
	local event = _getBindableEvent(name)
	return event.Event
end

-------------------------------------------------------------------------------------------------------------------------------------------------------

--  BindableFunctions !

-- Invoca um BindableFunction e espera a resposta.

function Network.InvokeBindable(name: string, ...: any): ...any
	local func = _getBindableFunction(name)
	return func:Invoke(...)
end

-- Registra o callback de um BindableFunction.

function Network.OnBindableInvoke(name: string, callback: (...any) -> ...any)
	local func = _getBindableFunction(name)
	func.OnInvoke = callback
end

----------------------------------------------------------------------------------------------------------------------------------------------------------

-- Funções útilitarias

-- prewarm é tipo micro ondas, ou seja, Pré-cria múltiplos eventos de uma só vez

function Network.Prewarm(config: PrewarmConfig)
	if IS_CLIENT then
		warn("[Network] Prewarm só deve ser chamado no servidor.")
		return
	end

	if config.remoteEvents then
		for _, name in ipairs(config.remoteEvents) do
			_getRemoteEvent(name)
		end
	end

	if config.remoteFunctions then
		for _, name in ipairs(config.remoteFunctions) do
			_getRemoteFunction(name)
		end
	end

	if config.bindableEvents then
		for _, name in ipairs(config.bindableEvents) do
			_getBindableEvent(name)
		end
	end

	if config.bindableFunctions then
		for _, name in ipairs(config.bindableFunctions) do
			_getBindableFunction(name)
		end
	end

	DebugPrint("Prewarm concluído.")
end

-- Retorna uma lista com todos os eventos criados até o momento.

function Network.GetEventList(): EventList
	local result: EventList = {
		RemoteEvents = {},
		RemoteFunctions = {},
		BindableEvents = {},
		BindableFunctions = {},
	}

	for name, _ in pairs(cache.RemoteEvents) do
		table.insert(result.RemoteEvents, name)
	end
	for name, _ in pairs(cache.RemoteFunctions) do
		table.insert(result.RemoteFunctions, name)
	end
	for name, _ in pairs(cache.BindableEvents) do
		table.insert(result.BindableEvents, name)
	end
	for name, _ in pairs(cache.BindableFunctions) do
		table.insert(result.BindableFunctions, name)
	end

	return result
end

--  Ativa ou desativa os logs de debug em tempo de execução.

function Network.SetDebug(enabled: boolean)
	CONFIG.DEBUG = enabled
end

-- Excluir Eventos, remotes e etc, não é útil e pode ser removido da versão final

-- até mourant resolver isso em uma function só, isso vai ficar separado

function Network.DestroyRemoteEvent(name: string)
	if IS_CLIENT then
		warn("[Network] Destroy só deve ser chamado no servidor.")
		return
	end

	local event = cache.RemoteEvents[name]
	if event then
		event:Destroy()
		cache.RemoteEvents[name] = nil
		Validators[name] = nil
		DebugPrint("RemoteEvent destruído:", name)
	end
end

return Network
