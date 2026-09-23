# Network

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Luau strict](https://img.shields.io/badge/luau-strict-informational.svg)

Uma camada leve sobre `RemoteEvent`, `RemoteFunction`, `BindableEvent` e `BindableFunction` no Roblox: cria e reutiliza esses objetos automaticamente por nome, com validação de entrada integrada (`Validators`) e separação explícita entre o que roda só no servidor.

## Índice

- [O que é o Network](#o-que-é-o-network)
- [Por que usar o Network?](#por-que-usar-o-network)
- [Conceitos rápidos](#conceitos-rápidos)
- [Como instalar](#como-instalar)
- [Onde colocar](#onde-colocar)
- [Cheatsheet](#cheatsheet)
- [RemoteEvents](#remoteevents)
- [RemoteFunctions](#remotefunctions)
- [Bindables](#bindables)
- [Validators](#validators)
- [Prewarm](#prewarm)
- [ServerOnly](#serveronly)
- [Limitações](#limitações)
- [Licença](#licença)

## O que é o Network

Em vez de criar e cachear `RemoteEvent`/`RemoteFunction`/`BindableEvent`/`BindableFunction` manualmente em cada script, você só chama uma função com o nome do evento — o `Network` cuida de criar (no servidor), esperar a criação (no cliente) e reutilizar a mesma instância depois:

```lua
local Network = require(game.ReplicatedStorage.Network)

-- Servidor
Network.OnServerEvent("PlayerScored"):Connect(function(player, points)
	print(player.Name, "marcou", points, "pontos")
end)

-- Cliente
Network.FireServer("PlayerScored", 10)
```

Escrito em Luau com `--!strict`, sem dependências externas.

## Por que usar o Network?

A pergunta certa não é "como o Network funciona", e sim: **o que muda pra quem usa, comparado a `RemoteEvent`/`RemoteFunction` puros?**

**Antes (Roblox puro):**

```lua
-- Servidor: alguém precisa criar o RemoteEvent, normalmente num script de inicialização
local dashRequest = Instance.new("RemoteEvent")
dashRequest.Name = "DashRequest"
dashRequest.Parent = game.ReplicatedStorage

dashRequest.OnServerEvent:Connect(function(player, direction, speed)
	-- a validação fica misturada com a lógica do dash
	if typeof(direction) ~= "Vector3" then
		return
	end
	if typeof(speed) ~= "number" or speed < 0 or speed > 100 then
		return
	end

	-- lógica do dash
end)

-- Cliente: precisa saber esperar a criação, com o próprio timeout
local dashRequest = game.ReplicatedStorage:WaitForChild("DashRequest", 10)
if not dashRequest then
	error("DashRequest não foi criado a tempo")
end
dashRequest:FireServer(direction, speed)
```

**Depois (com Network):**

```lua
-- Servidor: a validação fica separada da lógica
Network.SetValidator("DashRequest", function(player, direction, speed)
	if typeof(direction) ~= "Vector3" then
		return false, "Direção inválida"
	end
	if typeof(speed) ~= "number" or speed < 0 or speed > 100 then
		return false, "Velocidade inválida"
	end
	return true
end)

Network.OnServerEvent("DashRequest"):Connect(function(player, direction, speed)
	-- só a lógica do dash — se chegou aqui, já passou pela validação
end)

-- Cliente: sem criar nada, sem esperar nada na mão
Network.FireServer("DashRequest", direction, speed)
```

O que mudou, concretamente:

- **Sem instância pra gerenciar.** Nenhum script de gameplay cria, nomeia ou dá `Parent` a um `RemoteEvent`. Você nem precisa saber se é o servidor ou o cliente que cria o objeto — o `Network` decide isso por trás.
- **Validação como responsabilidade separada.** O `Validator` decide se os dados podem passar; o callback decide o que fazer com eles. Isso também vale para `Once`/`Wait`: os dois ignoram automaticamente um evento que o validador rejeitou, sem você escrever esse `while true` na mão.
- **Erros que dizem o que fazer.** Em vez de descobrir na hora errada que um `RemoteEvent` nunca foi criado, você recebe uma mensagem dizendo exatamente isso — e sugerindo `Network.Prewarm`.

**O que o Network não resolve por você**, pra não vender mais do que ele entrega:

- Ele **não valida nada sozinho**. Sem um `Validator`, um evento aceita qualquer coisa — exatamente como um `RemoteEvent` puro.
- Nomes são strings. Um typo só aparece em runtime; `Network.GetEventList()` ajuda a checar o que já existe, mas não é autocomplete.
- `InvokeClient` continua **exatamente tão arriscado quanto o nativo** — o Network não resolve esse problema, só avisa sobre ele (veja [Limitações](#limitações)).

Ou seja: o ganho real não é "fazer mágica", é tirar boilerplate repetitivo do caminho e dar um lugar organizado pra validação — o resto continua sendo Roblox puro por baixo.

## Conceitos rápidos

Se você já conhece Luau, pode pular esta seção. Alguns pontos que aparecem bastante no código e nos exemplos:

- **Callback**: uma função que você entrega como argumento para outra função, para ser chamada depois (não na hora em que você a passa). É o `function(player, value) ... end` que você escreve dentro de `:Connect(...)`.
- **`self` e o `_`**: em `Connect`, `Once` e `Wait`, o primeiro parâmetro (escrito como `_`) é o `self` do método — por isso você chama `algo:Connect(...)` com dois-pontos em vez de `algo.Connect(...)`. Ele é aceito só por consistência de assinatura, mesmo sem ser usado dentro da função.
- **`...` e `any`**: `...any` significa "qualquer quantidade de argumentos, de qualquer tipo". É assim que `FireServer`, `FireClient`, `InvokeServer` etc. deixam você mandar o que quiser (uma string, vários números, uma tabela...).
- **`-> ()` e `-> (boolean, string?)`**: depois da seta (`->`) vem o tipo de retorno da função. `()` sozinho significa que ela não retorna nada (o equivalente a "void"). Um `Validator` retorna `(boolean, string?)`: um `true`/`false` dizendo se passou, e opcionalmente uma `string` (o `?` indica que pode ser `nil`) explicando o motivo da rejeição.

## Como instalar

**Com Rojo** (recomendado se você já sincroniza o projeto com o Studio): copie `Network.luau` para dentro do seu projeto e aponte um caminho em `ReplicatedStorage` para ele no seu `default.project.json`, ou use o `default.project.json` deste repositório como ponto de partida.

**Manual**: baixe `Network.luau`, arraste para dentro de `ReplicatedStorage` no Explorer do Studio e garanta que o `ClassName` seja `ModuleScript`.

Este repositório não está publicado no Wally. Veja o motivo em [Limitações](#limitações) antes de empacotar o módulo assim.

## Onde colocar

O módulo **precisa** estar em `ReplicatedStorage`, ou em qualquer lugar que servidor e cliente acessem pelo mesmo caminho.

Isso importa porque `Network` trata cliente e servidor de forma diferente ao criar um `RemoteEvent`/`RemoteFunction`: o **servidor cria** o objeto na primeira vez que ele é pedido; o **cliente espera** essa criação com um `WaitForChild` com timeout. Se o módulo estiver em `ServerScriptService`, o cliente nunca vai conseguir `require` nele. Se estiver só em `StarterPlayerScripts`, o servidor não tem como criar nada ali.

## Cheatsheet

Referência rápida de toda a API. Para explicação e exemplos completos, veja as seções abaixo.

Exemplo completo em CHEATSHEET.md

| Função | O que faz | Exemplo |
|---|---|---|
| `FireServer(name, ...)` | Cliente → Servidor | `Network.FireServer("DashRequest", dir, 50)` |
| `FireClient(name, player, ...)` | Servidor → 1 cliente | `Network.FireClient("Loot", player, "Espada")` |
| `FireAllClients(name, ...)` | Servidor → todos os clientes | `Network.FireAllClients("Anuncio", "Oi")` |
| `FireExceptClient(name, player, ...)` | Servidor → todos, menos 1 | `Network.FireExceptClient("Anuncio", p, "Oi")` |
| `OnClientEvent(name):Connect(fn)` | Cliente escuta o servidor | `Network.OnClientEvent("Loot"):Connect(fn)` |
| `OnServerEvent(name):Connect(fn)` | Servidor escuta o cliente | `Network.OnServerEvent("X"):Connect(fn)` |
| `OnServerEvent(name):Once(fn)` | Só a 1ª vez válida | `Network.OnServerEvent("X"):Once(fn)` |
| `OnServerEvent(name):Wait()` | Pausa até 1 evento válido | `local p, v = Network.OnServerEvent("X"):Wait()` |
| `InvokeServer(name, ...)` | Cliente pergunta, servidor responde | `local r = Network.InvokeServer("GetInventory")` |
| `OnServerInvoke(name, fn)` | Servidor responde ao cliente | `Network.OnServerInvoke("GetInventory", fn)` |
| `InvokeClient(name, player, ...)` ⚠️ | Servidor pergunta, cliente responde — **bloqueia a thread, sem timeout** | veja [Limitações](#limitações) |
| `OnClientInvoke(name, fn)` | Cliente responde ao servidor | `Network.OnClientInvoke("Confirmar", fn)` |
| `FireBindable(name, ...)` | Mesmo contexto (servidor OU cliente) | `Network.FireBindable("PlayerDied", player)` |
| `OnBindableEvent(name):Connect(fn)` | Mesmo contexto | `Network.OnBindableEvent("PlayerDied"):Connect(fn)` |
| `InvokeBindable(name, ...)` | Mesmo contexto | `Network.InvokeBindable("CalcularDano", 10, 1.5)` |
| `OnBindableInvoke(name, fn)` | Mesmo contexto | `Network.OnBindableInvoke("CalcularDano", fn)` |
| `SetValidator(name, fn)` | Registra validação de entrada | veja [Validators](#validators) |
| `RemoveValidator(name)` | Remove a validação | `Network.RemoveValidator("DashRequest")` |
| `Prewarm({ ... })` | Cria vários eventos de uma vez | veja [Prewarm](#prewarm) |
| `GetEventList()` | Lista tudo o que já foi criado | `Network.GetEventList()` |
| `SetDebug(true/false)` | Liga/desliga logs internos | `Network.SetDebug(true)` |

## RemoteEvents

```lua
-- Servidor -> Cliente
Network.FireClient("Loot", player, "Espada")
Network.FireAllClients("Anuncio", "O servidor vai reiniciar em 5 minutos")
Network.FireExceptClient("Anuncio", jogadorQueJaSabe, "...")

-- Cliente escutando o servidor
Network.OnClientEvent("Loot"):Connect(function(item)
	print("Recebi:", item)
end)

-- Cliente -> Servidor
Network.FireServer("PlayerScored", 10)

-- Servidor escutando o cliente
Network.OnServerEvent("PlayerScored"):Connect(function(player, points)
	print(player.Name, points)
end)
```

`Network.OnServerEvent(name)` sempre devolve o mesmo tipo de objeto, com três métodos:

- **`:Connect(callback)`** — chama `callback` a cada evento válido.
- **`:Once(callback)`** — chama `callback` apenas na primeira vez que um evento **válido** chegar; eventos inválidos (rejeitados por um `Validator`) não contam e não consomem o `Once`.
- **`:Wait()`** — pausa a thread atual até chegar um evento válido, e o devolve (`player, ...`). Também ignora eventos inválidos e continua esperando.

Mais exemplos em [`examples/RemoteEvents.server.luau`](examples/RemoteEvents.server.luau) e [`examples/RemoteEvents.client.luau`](examples/RemoteEvents.client.luau).

## RemoteFunctions

```lua
-- Cliente pergunta, servidor responde
local inventario = Network.InvokeServer("GetInventory")

Network.OnServerInvoke("GetInventory", function(player)
	return { "Espada", "Escudo" }
end)
```

> **Atenção com `InvokeClient`**. Veja [Limitações](#limitações) antes de usar — é a única função da API que pode travar a thread do servidor indefinidamente.

Mais exemplos em [`examples/RemoteFunctions.server.luau`](examples/RemoteFunctions.server.luau) e [`examples/RemoteFunctions.client.luau`](examples/RemoteFunctions.client.luau).

## Bindables

`BindableEvent`/`BindableFunction` só funcionam **dentro do mesmo contexto** — servidor com servidor, cliente com cliente. Eles nunca atravessam a rede; para isso, use RemoteEvents/RemoteFunctions.

```lua
Network.OnBindableEvent("PlayerDied"):Connect(function(player)
	print(player.Name, "morreu")
end)

Network.FireBindable("PlayerDied", player) -- em outro script do MESMO lado
```

Por dentro, cada VM (servidor e cliente) tem seu próprio `BindableEvent`/`BindableFunction`, sem `Parent` — por isso eles nunca se confundem com o do outro lado, mesmo com o mesmo nome.

Mais exemplos em [`examples/Bindables.server.luau`](examples/Bindables.server.luau).

## Validators

Um `Validator` roda no servidor, antes do callback, para RemoteEvents (`OnServerEvent`) e RemoteFunctions (`OnServerInvoke`) com o mesmo nome:

```lua
Network.SetValidator("BuyItem", function(player, itemId)
	if type(itemId) ~= "number" or itemId <= 0 then
		return false, "itemId inválido"
	end
	return true
end)

Network.OnServerEvent("BuyItem"):Connect(function(player, itemId)
	-- só chega aqui se o validador aprovou
end)

Network.RemoveValidator("BuyItem") -- volta a aceitar tudo
```

Pontos importantes:

- O validador é consultado **no momento em que o evento chega**, não em que você chama `SetValidator`/`OnServerEvent`. Isso significa que dá para registrar, trocar ou remover um validador com o servidor já rodando, e isso vale imediatamente para todos os listeners existentes.
- Se a validação falhar num `OnServerEvent`, o callback simplesmente não é chamado (e `Once`/`Wait` continuam esperando). Se falhar num `OnServerInvoke`, o `InvokeServer` do cliente recebe `nil` — o motivo da rejeição aparece só no `warn()` do servidor, para não ensinar as regras de validação a quem estiver tentando burlar.
- O validador roda dentro de um `pcall`: se ele mesmo der erro (por exemplo, indexar um argumento que veio `nil`), o evento é só rejeitado com um aviso — o listener continua funcionando normalmente depois.
- Um `RemoteEvent` e um `RemoteFunction` **não podem ter o mesmo nome**, porque os validadores são indexados só pelo nome (sem isso, um validador valeria para os dois ao mesmo tempo por engano). O módulo recusa a criação com um erro explicativo.

Mais exemplos em [`examples/Validators.server.luau`](examples/Validators.server.luau).

## Prewarm

Cria vários eventos de uma vez, em vez de deixar cada um ser criado sob demanda no primeiro `Fire`/`Connect`/`Invoke`:

```lua
Network.Prewarm({
	remoteEvents = { "PlayerScored", "Anuncio" },
	remoteFunctions = { "GetInventory", "BuyItem" },
	bindableEvents = { "PlayerDied" },
	bindableFunctions = { "CalcularDano" },
})
```

Chame isso uma vez no início do servidor. Isso reduz a chance de um cliente tentar usar um evento antes do servidor ter tido a chance de criá-lo (o que gera o erro de timeout descrito em [Onde colocar](#onde-colocar)).

Exemplo completo em [`examples/Prewarm.server.luau`](examples/Prewarm.server.luau).

## ServerOnly

`SERVER_ONLY_EVENTS`/`SERVER_ONLY_FUNCTIONS`, dentro do próprio `Network.luau`, marcam nomes de Bindables que só devem ser usados no servidor. Pedir um desses nomes no cliente gera um erro explicativo, em vez de criar um `BindableEvent` separado (lembre-se: cada VM tem o seu) que ninguém nunca dispara.

```lua
-- Dentro de Network.luau
local SERVER_ONLY_EVENTS: { [string]: boolean } = {
	PlayerDamaged = true,
}
```

**Isto não é segurança.** O cliente consegue ler essa lista normalmente (ela está em `ReplicatedStorage`). Ela só existe para evitar um erro de uso silencioso. A proteção real de qualquer coisa sensível continua sendo os `Validators`, que rodam no servidor.

## Limitações

- **`InvokeClient` bloqueia a thread do servidor, sem timeout.** Isso não é um comportamento do `Network` — é assim que o `RemoteFunction:InvokeClient` nativo do Roblox funciona, e o `Network.InvokeClient` é só um repasse direto para ele. Se o cliente demorar, nunca responder ou desconectar enquanto o servidor espera, essa thread pode ficar pendurada. Evite usar em fluxos críticos ou com clientes que você não controla; para pedir algo ao cliente com um limite de tempo, prefira montar um padrão de pedido/resposta com dois `RemoteEvent`s e um timeout seu.
- **`ServerOnly` não é segurança** — veja a seção acima.
- **`RemoteEvent` e `RemoteFunction` não podem compartilhar o mesmo nome** (os `Validators` são indexados só pelo nome).
- **Não existe API de destruição.** Uma vez criado, um `RemoteEvent`/`RemoteFunction`/`BindableEvent`/`BindableFunction` vive até o fim da sessão do servidor (ou até o cliente desconectar, no caso dos bindables do cliente). Isso foi uma escolha deliberada, para manter a API pequena.
- **Registrar um segundo `OnServerInvoke`/`OnClientInvoke`/`OnBindableInvoke` para o mesmo nome substitui o callback anterior silenciosamente**, com só um `warn()` — não é um erro, então preste atenção nos avisos do console.
- **`SERVER_ONLY_*` fica dentro do próprio módulo.** Se você distribuir isso via um gerenciador de pacotes que sobrescreve o arquivo inteiro a cada atualização (como o Wally), a sua lista personalizada seria perdida na próxima vez que atualizar. Por isso este repositório não está publicado dessa forma — prefira copiar o arquivo diretamente ou sincronizar via Rojo.

## Licença

[MIT](LICENSE).