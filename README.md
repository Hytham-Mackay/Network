# Network

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Luau strict](https://img.shields.io/badge/luau-strict-informational.svg)

Uma camada leve sobre `RemoteEvent`, `RemoteFunction`, `BindableEvent` e `BindableFunction` no Roblox: cria e reutiliza esses objetos automaticamente por nome, com validação de entrada integrada (`Validators`) e separação explícita entre o que roda só no servidor.

## Índice

- [O que é o Network](#o-que-é-o-network)
- [Conceitos rápidos](#conceitos-rápidos)
- [Como instalar](#como-instalar)
- [Onde colocar](#onde-colocar)
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
