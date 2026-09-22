local Players = game:GetService("Players")
local Network = require(game.ReplicatedStorage.Network)

-- Escuta o cliente
Network.OnServerEvent("PlayerScored"):Connect(function(player, points: number)
	print(player.Name, "marcou", points, "pontos")
end)

-- Avisa todo mundo quando alguém entra
Players.PlayerAdded:Connect(function(player)
	Network.FireAllClients("PlayerJoined", player.Name)
end)
