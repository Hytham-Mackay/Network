# Network Module — Biblioteca de Sintaxes

Referência rápida para copiar e colar. Para entender o _porquê_ de cada decisão, veja o README.

## 0. Importando o módulo

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network = require(ReplicatedStorage.Network) -- ajuste o caminho conforme sua estrutura
```

`require()` é chamado uma vez por VM (servidor, e cada cliente) — Lua cacheia o retorno, então todos os scripts do mesmo lado que dão `require` recebem a mesma tabela `Network`, com o mesmo `cache` por baixo.

---

## 1. RemoteEvent

### 1.1 Client → Server (com validação)

```lua
-- Servidor
Network.SetValidator("RequestX", function(player, ...)
	-- retorne true/false, "motivo opcional"
	return true
end)

Network.OnServerEvent("RequestX"):Connect(function(player, ...)
	-- lógica
end)

-- Pra desativar a validação depois (o evento continua existindo, só a regra sai):
-- Network.RemoveValidator("RequestX")
```

```lua
-- Cliente
Network.FireServer("RequestX", arg1, arg2)
```

### 1.2 Client → Server (sem validação)

```lua
-- Servidor
Network.OnServerEvent("RequestY"):Connect(function(player, ...)
	-- lógica
end)
```

```lua
-- Cliente
Network.FireServer("RequestY", arg1)
```

### 1.3 Server → Client

```lua
-- Um jogador específico
Network.FireClient("Notify", player, "mensagem")

-- Todos os jogadores
Network.FireAllClients("MatchStarted", matchId)

-- Todos, menos um
Network.FireExceptClient("Celebration", winningPlayer)
```

```lua
-- Cliente escuta
Network.OnClientEvent("Notify"):Connect(function(message)
	-- lógica
end)
```

### 1.4 Once / Wait

```lua
-- :Once — só a primeira vez que um evento VÁLIDO chegar. Eventos rejeitados por um
-- Validator não contam e não consomem o Once.
Network.OnServerEvent("RequestX"):Once(function(player, ...)
	-- lógica
end)

-- :Wait — pausa a thread atual até chegar um evento válido, e o devolve
local player, arg1, arg2 = Network.OnServerEvent("RequestX"):Wait()
```

---

## 2. RemoteFunction

### 2.1 Client → Server (pede e espera resposta)

```lua
-- Servidor
Network.OnServerInvoke("GetInventory", function(player)
	return getInventoryFor(player)
end)
```

```lua
-- Cliente
local items = Network.InvokeServer("GetInventory")
```

`SetValidator`/`RemoveValidator` também valem aqui, do mesmo jeito que na 1.1 — o validador roda antes do callback de `OnServerInvoke`.

### 2.2 Server → Client (evite quando possível — ver Limitações no README)

```lua
-- Cliente
Network.OnClientInvoke("ConfirmTrade", function(tradeId)
	return promptUser(tradeId)
end)
```

```lua
-- Servidor
local confirmed = Network.InvokeClient("ConfirmTrade", player, tradeId)
```

---

## 3. BindableEvent

### 3.1 Uso comum (mesmo lado — servidor com servidor, ou cliente com cliente)

```lua
Network.FireBindable("PlayerDamaged", player, amount)

Network.OnBindableEvent("PlayerDamaged"):Connect(function(player, amount)
	-- lógica
end)
```

### 3.2 Exclusivo do servidor

```lua
-- No topo do Network.luau
local SERVER_ONLY_EVENTS = {
	CombatTick = true,
}
```

```lua
-- Servidor — funciona normalmente
Network.FireBindable("CombatTick", deltaTime)
Network.OnBindableEvent("CombatTick"):Connect(function(deltaTime)
	-- lógica
end)

-- Cliente chamando "CombatTick" -> error() imediato
```

---

## 4. BindableFunction

### 4.1 Uso comum

```lua
Network.OnBindableInvoke("CanAfford", function(player, price)
	return getBalance(player) >= price
end)

local ok = Network.InvokeBindable("CanAfford", player, 100)
```

### 4.2 Exclusivo do servidor

```lua
-- No topo do Network.luau
local SERVER_ONLY_FUNCTIONS = {
	GetServerTick = true,
}
```

```lua
-- Servidor — funciona normalmente
local tick = Network.InvokeBindable("GetServerTick")

-- Cliente chamando "GetServerTick" -> error() imediato
```

---

## 5. Prewarm — criar tudo antecipadamente (só servidor)

```lua
Network.Prewarm({
	remoteEvents = {"RequestX", "Notify"},
	remoteFunctions = {"GetInventory"},
	bindableEvents = {"PlayerDamaged", "CombatTick"},
	bindableFunctions = {"CanAfford"},
})
```

## 6. Debug

```lua
Network.SetDebug(true) -- liga os prints [Network] só do lado onde foi chamado
```

## 7. Inspecionar o que já foi criado (nesse lado)

```lua
local list = Network.GetEventList()
-- list.RemoteEvents, list.RemoteFunctions, list.BindableEvents, list.BindableFunctions
```

---

## 8. Checklist rápido para adicionar um evento novo

- [ ] Escolher o tipo certo (tabela abaixo)
- [ ] Nome lógico, sem espaços (ex.: `PlayerDamaged`). **Atenção**: `RemoteEvent` e `RemoteFunction` compartilham o mesmo espaço de nomes — não podem usar o mesmo nome entre si (os `Validators` são indexados só pelo nome). `BindableEvent`/`BindableFunction` têm espaços de nomes próprios e podem repetir um nome já usado em `RemoteEvent`/`RemoteFunction` sem problema
- [ ] Decidir se precisa de `SetValidator` — vale tanto para `RemoteEvent` (recebido via `OnServerEvent`) quanto para `RemoteFunction` (recebido via `OnServerInvoke`), sempre do lado do servidor
- [ ] Se for `BindableEvent`/`BindableFunction` exclusivo do servidor, adicionar em `SERVER_ONLY_EVENTS`/`SERVER_ONLY_FUNCTIONS`
- [ ] Decidir se entra no `Prewarm` ou se a criação lazy (no primeiro uso) é suficiente
- [ ] Implementar quem **escuta** (`On*`) antes de testar quem **dispara** (ou usar `Prewarm`) — evita o timeout do cliente esperando um `RemoteEvent`/`RemoteFunction` que o servidor ainda não criou

### Qual tipo usar?

| Preciso de...                                                    | Use                                                              |
| ---------------------------------------------------------------- | ---------------------------------------------------------------- |
| Servidor avisar cliente(s), sem esperar resposta                 | `RemoteEvent` — `FireClient`/`FireAllClients`/`FireExceptClient` |
| Cliente avisar o servidor, sem esperar resposta                  | `RemoteEvent` — `FireServer`                                     |
| Cliente pedir algo ao servidor e esperar resposta                | `RemoteFunction` — `InvokeServer`                                |
| Servidor pedir algo ao cliente e esperar resposta (evite se der) | `RemoteFunction` — `InvokeClient`                                |
| Comunicação interna, mesmo lado, sem resposta                    | `BindableEvent`                                                  |
| Comunicação interna, mesmo lado, com resposta                    | `BindableFunction`                                               |
| Dois módulos fortemente relacionados, mesmo lado                 | Chamada direta via `require()`, sem passar pelo Network          |
