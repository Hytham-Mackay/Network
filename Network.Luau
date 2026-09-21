--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Network = {}

-------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Tipos públicos (acessíveis por quem usa o módulo, ex.: Network.ServerEvent)

-- Função de validação registrada com SetValidator (vale para OnServerEvent e para OnServerInvoke).
-- Retorna true/false e, opcionalmente, o motivo da falha.
export type Validator = (player: Player, ...any) -> (boolean, string?)

-- Objeto retornado por Network.OnServerEvent
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

-------------------------------------------------------------------------------------------------------------------------------------------------------------

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

-- Nomes de BindableEvents que existem só no servidor.
-- Pedir um desses nomes no cliente gera um erro explicativo, em vez de criar um bindable
-- separado (cada VM tem o seu) que ninguém nunca dispara.
-- Isto NÃO é segurança: o cliente consegue ler esta lista. A proteção real fica nos validadores do servidor.
-- Edite conforme o seu projeto, por exemplo:
--   PlayerDamaged = true,

local SERVER_ONLY_EVENTS: { [string]: boolean } = {}

-- Mesma ideia, mas para BindableFunctions

local SERVER_ONLY_FUNCTIONS: { [string]: boolean } = {}

--------------------------------------------------------------------------------------------------------------------------------------

-- Tabelas de cache separadas por tipo

local cache: {
	RemoteEvents: { [string]: RemoteEvent },
	RemoteFunctions: { [string]: RemoteFunction },
	BindableEvents: { [string]: BindableEvent },
	BindableFunctions: { [string]: BindableFunction },
} =
	{

		RemoteEvents = {},
		RemoteFunctions = {},
		BindableEvents = {},
		BindableFunctions = {},
	}

-- Validadores registrados para RemoteEvents e RemoteFunctions

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

-- Registro dos callbacks já atribuídos (OnServerInvoke, OnClientInvoke e OnBindableInvoke).
-- Não dá para ler esses callbacks de volta pela instância, então o módulo guarda por conta própria
-- quais nomes já foram registrados, para avisar quando um callback for substituído.

local registeredCallbacks: { [string]: boolean } = {}

local function _markCallback(kind: string, name: string)
	local key = kind .. ":" .. name

	if registeredCallbacks[key] then
		warn(
			string.format(
				"[Network] %s('%s') já tinha um callback registrado. O anterior foi substituído.",
				kind,
				name
			)
		)
	end

	registeredCallbacks[key] = true
end

---------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Parte importante bebê

-- Obtenção de eventos + cache e criação autmática + Profissionalismo Mourant

-- Classes permitidas nos helpers internos: restringe o className na checagem de tipos
type RemoteClass = "RemoteEvent" | "RemoteFunction"
type BindableClass = "BindableEvent" | "BindableFunction"

-- Lógica comum de RemoteEvent e RemoteFunction (a única diferença é a classe, o prefixo e a tabela de cache):
--   cache -> nome real -> objeto existente? -> cliente espera / servidor cria -> valida ClassName -> cache
-- Os wrappers _getRemoteEvent e _getRemoteFunction, logo abaixo, só escolhem esses três parâmetros.
-- O "T" é o tipo guardado no cache (RemoteEvent ou RemoteFunction) e é inferido a partir da tabela recebida.

local function _getRemote<T>(className: RemoteClass, prefix: string, store: { [string]: T }, name: string): T
	-- verifica cache primeiro
	local cached = store[name]
	if cached ~= nil then
		return cached
	end

	local realName = prefix .. name

	local existing = script:FindFirstChild(realName)

	local object: Instance

	if existing then
		object = existing
	elseif IS_CLIENT then
		-- Aqui o cliente deve esperar o servidor criar
		DebugPrint("Cliente aguardando " .. className .. ":", realName)

		local waited = script:WaitForChild(realName, CONFIG.WAIT_TIMEOUT)

		if not waited then
			error(
				string.format(
					"[Network] Timeout: %s '%s' não foi criado pelo servidor em %d segundos. "
						.. "Verifique se o servidor criou esse objeto (ou chamou Network.Prewarm) antes do cliente tentar usá-lo.",
					className,
					name,
					CONFIG.WAIT_TIMEOUT
				)
			)
		end

		object = waited
	else
		-- Servidor cria o objeto
		DebugPrint("Servidor criando " .. className .. ":", realName)

		local created = Instance.new(className)
		created.Name = realName
		created.Parent = script

		object = created
	end

	-- Proteção pra ter certeza que é do tipo esperado (vale para objeto já existente e para o que o cliente esperou)
	if not object:IsA(className) then
		error(
			string.format(
				'[Network] Objeto "%s" já existe no módulo, mas não é um %s (é %s). '
					.. "Verifique se não há conflito de nomes com outro tipo de instância.",
				realName,
				className,
				object.ClassName
			)
		)
	end

	-- O IsA com className dinâmico não refina o tipo, então o cast para any fica só aqui, num lugar central.
	-- A segurança de tipo para quem chama continua nos wrappers, que declaram o retorno.
	store[name] = object :: any
	return object :: any
end

-- Os validadores são indexados só pelo nome. Para um validador nunca valer por engano para um
-- RemoteEvent E para um RemoteFunction ao mesmo tempo, o mesmo nome não pode ser usado nos dois tipos.

local function _getRemoteEvent(name: string): RemoteEvent
	if cache.RemoteFunctions[name] then
		error(
			string.format(
				'[Network] O nome "%s" já é usado por um RemoteFunction. '
					.. "RemoteEvent e RemoteFunction não podem ter o mesmo nome (os validadores são indexados pelo nome).",
				name
			)
		)
	end

	return _getRemote("RemoteEvent", CONFIG.PREFIX_REMOTE_EVENT, cache.RemoteEvents, name)
end

local function _getRemoteFunction(name: string): RemoteFunction
	if cache.RemoteEvents[name] then
		error(
			string.format(
				'[Network] O nome "%s" já é usado por um RemoteEvent. '
					.. "RemoteEvent e RemoteFunction não podem ter o mesmo nome (os validadores são indexados pelo nome).",
				name
			)
		)
	end

	return _getRemote("RemoteFunction", CONFIG.PREFIX_REMOTE_FUNCTION, cache.RemoteFunctions, name)
end

-------------------------------------------------------------------------------------------------------------------------------------

-- Lógica comum de BindableEvent e BindableFunction:
--   server-only? -> cache -> cria -> cache
--
-- Bindables são mantidos sem Parent para que cada VM (servidor e cliente) possua a sua própria instância.
-- Eles não são usados para comunicação entre servidor e cliente: cada contexto executa a sua cópia
-- do módulo, com o seu próprio cache, e nada disso é replicado.

local function _getBindable<T>(
	className: BindableClass,
	prefix: string,
	serverOnly: { [string]: boolean },
	store: { [string]: T },
	name: string
): T
	if serverOnly[name] and IS_CLIENT then
		error(
			string.format(
				'[Network] Acesso do cliente bloqueado a %s "%s": este nome está marcado como server-only.',
				className,
				name
			)
		)
	end

	local cached = store[name]
	if cached ~= nil then
		return cached
	end

	local realName = prefix .. name

	DebugPrint("Criando " .. className .. " (local a este contexto):", realName)
	local object = Instance.new(className)
	object.Name = realName
	-- Sem object.Parent — ver a nota acima de _getBindable.

	store[name] = object :: any
	return object :: any
end

local function _getBindableEvent(name: string): BindableEvent
	return _getBindable("BindableEvent", CONFIG.PREFIX_BINDABLE_EVENT, SERVER_ONLY_EVENTS, cache.BindableEvents, name)
end

local function _getBindableFunction(name: string): BindableFunction
	return _getBindable(
		"BindableFunction",
		CONFIG.PREFIX_BINDABLE_FUNCTION,
		SERVER_ONLY_FUNCTIONS,
		cache.BindableFunctions,
		name
	)
end
-----------------------------------------------------------------------------------------------------------------------------------

-- Sistema de validação, mesma ideia padrão, validar no servidor e não no cliente

-- Outra parte importante, o any em players serve para receber qualquer quantidade de argumentos

-- boolean retorna true e false enquanto string? significa que pode ser nil, ai é so para o motivo de falha na validação
-- (essa assinatura agora está no tipo exportado Validator, lá em cima)

-- O validador vale para o RemoteEvent (OnServerEvent) OU para o RemoteFunction (OnServerInvoke) com esse nome.

function Network.SetValidator(EventName: string, validator: Validator)
	if IS_CLIENT then
		warn("[Network] Validadores só devem ser registrados no servidor. Ignorando.")
		return
	end

	assert(type(EventName) == "string" and EventName ~= "", "[Network] EventName precisa ser uma string não vazia.")

	assert(type(validator) == "function", "[Network] Validator precisa ser uma função.")

	Validators[EventName] = validator
	DebugPrint("Validador registrado para:", EventName)
end

-- Helper interno usado pelo OnServerEvent (Connect, Once e Wait) e pelo OnServerInvoke.
-- O validador é buscado em Validators[name] NO MOMENTO DO DISPARO, e não quando o
-- OnServerEvent/OnServerInvoke é chamado. Assim, SetValidator/RemoveValidator valem para todos os
-- listeners, mesmo os que foram conectados antes.
-- Retorna true se o evento pode seguir para o callback, false se deve ser ignorado.

local function _runValidator(name: string, player: Player, ...: any): boolean
	local validator = Validators[name]

	-- Validador é opcional: sem validador, o evento sempre passa
	if not validator then
		return true
	end

	-- pcall porque o cliente controla os argumentos: um validador que não espera
	-- um tipo (ex.: indexar um nil) lançaria erro. Nesse caso o evento é rejeitado.
	local success, ok, err = pcall(validator, player, ...)

	if not success then
		-- Quando pcall falha, "ok" contém a mensagem de erro (por isso o tostring)
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
				err or "motivo desconhecido"
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
-- Sempre retorna o mesmo tipo de objeto (ServerEvent), com Connect, Once e Wait, exista ou não um validador.
-- Se houver um validador registrado para esse evento (a qualquer momento, antes ou depois
-- deste OnServerEvent ser chamado), ele será executado antes do callback.
-- Se falhar, o callback não é chamado.

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

-- Registra o callback que o servidor executa quando o cliente invoca.
-- Se houver um validador registrado para esse nome (a qualquer momento), ele roda antes do callback.
-- Se a validação falhar, o InvokeServer do cliente recebe nil. O motivo aparece só no warn do servidor,
-- para não entregar ao cliente informação sobre as regras de validação.

function Network.OnServerInvoke(name: string, callback: (Player, ...any) -> ...any)
	if IS_CLIENT then
		error("[Network] OnServerInvoke só pode ser chamado do servidor.")
	end

	local func = _getRemoteFunction(name)

	_markCallback("OnServerInvoke", name)

	func.OnServerInvoke = function(player: Player, ...: any): ...any
		if not _runValidator(name, player, ...) then
			return nil
		end

		return callback(player, ...)
	end
end

-- o contrário, registra o callback que o cliente executa quando o servidor invoca

function Network.OnClientInvoke(name: string, callback: (...any) -> ...any)
	if IS_SERVER then
		error("[Network] OnClientInvoke só pode ser chamado do cliente.")
	end

	local func = _getRemoteFunction(name)

	_markCallback("OnClientInvoke", name)

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

	_markCallback("OnBindableInvoke", name)

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
