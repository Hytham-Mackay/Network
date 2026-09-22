local Network = require(game.ReplicatedStorage.Network)

Network.OnClientEvent("PlayerJoined"):Connect(function(playerName: string)
	print(playerName, "entrou no jogo")
end)

Network.FireServer("PlayerScored", 10)
