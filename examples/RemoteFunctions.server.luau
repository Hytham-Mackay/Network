local Network = require(game.ReplicatedStorage.Network)

-- O cliente pergunta algo e espera uma resposta.
Network.OnServerInvoke("GetInventory", function(player)
	return { "Espada", "Escudo", "Poção" }
end)

-- CUIDADO: InvokeClient bloqueia a thread do servidor até o cliente responder,
-- sem nenhum timeout embutido (é assim que o RemoteFunction nativo do Roblox
-- funciona). Veja "Limitações" no README antes de usar isto num fluxo crítico
-- ou com clientes que você não controla.
-- local resposta = Network.InvokeClient("Confirmar", player, "Tem certeza?")
