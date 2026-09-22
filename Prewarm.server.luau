local Network = require(game.ReplicatedStorage.Network)

-- Cria todos os eventos de uma vez, no início do servidor, em vez de deixar
-- cada um ser criado sob demanda no primeiro Fire/Connect/Invoke. Isso reduz
-- a chance de um cliente tentar usar um evento antes do servidor ter tido a
-- chance de criá-lo.
Network.Prewarm({
	remoteEvents = { "PlayerScored", "PlayerJoined" },
	remoteFunctions = { "GetInventory", "BuyItem" },
	bindableEvents = { "PlayerDied" },
	bindableFunctions = { "CalcularDano" },
})
