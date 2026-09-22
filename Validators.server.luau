local Network = require(game.ReplicatedStorage.Network)

-- O validador roda ANTES do callback, sempre no servidor. Pode ser registrado
-- antes ou depois do Connect — ele é buscado no momento em que o evento chega,
-- não no momento em que você chama SetValidator.
Network.SetValidator("BuyItem", function(player, itemId: number)
	if type(itemId) ~= "number" then
		return false, "itemId precisa ser um número"
	end
	if itemId <= 0 then
		return false, "itemId inválido"
	end
	return true
end)

Network.OnServerEvent("BuyItem"):Connect(function(player, itemId: number)
	-- Se chegou aqui, já passou pelo validador acima.
	print(player.Name, "comprou o item", itemId)
end)

-- Para desativar a validação depois (o evento continua existindo, só a regra sai):
-- Network.RemoveValidator("BuyItem")
