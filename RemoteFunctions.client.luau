local Network = require(game.ReplicatedStorage.Network)

local inventario = Network.InvokeServer("GetInventory")
print(inventario)

-- Callback para quando o SERVIDOR usa InvokeClient (veja a ressalva no README).
Network.OnClientInvoke("Confirmar", function(mensagem: string)
	print("Servidor perguntou:", mensagem)
	return true
end)
