local Network = require(game.ReplicatedStorage.Network)

-- BindableEvents/Functions só valem DENTRO do mesmo contexto (servidor OU
-- cliente). Não atravessam a fronteira de rede — para isso, use
-- RemoteEvents/RemoteFunctions.

Network.OnBindableEvent("PlayerDied"):Connect(function(player)
	print(player.Name, "morreu")
end)

Network.OnBindableInvoke("CalcularDano", function(base: number, multiplicador: number)
	return base * multiplicador
end)

-- Em outro script do servidor:
-- Network.FireBindable("PlayerDied", player)
-- local dano = Network.InvokeBindable("CalcularDano", 10, 1.5)
