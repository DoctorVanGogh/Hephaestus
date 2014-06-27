-----------------------------------------------------------------------------------------------
-- frFR Localization for Hephaestus
-- Copyright (c) DoctorVanGogh on Wildstar forums - All Rights reserved
-----------------------------------------------------------------------------------------------

local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("Hephaestus", "frFR")
if not L then return end
L["QueueHeader"] = "Artisanat, file d'attente"
L["QueueStart"] = "Commencer"
L["QueueStop"] = "Arr\195\170ter"
L["QueueClear"] = "Vider"
L["RepeatHeader"] = "Ajouter \195\160 la file d'attente"
L["RepeatCostPerItem"] = "Co\195\187t par pi\195\168ce :"
L["RepeatCostTotal"] = "Co\195\187t total :"
L["RepeatAdd"] = "Ajouter"
L["BlockerMounted"] = "N'est pas sur une monture : %s"
L["BlockerCraftingStation"] = "Est \195\160 une station d'artisanat : %s"
L["BlockerAbility"] = "N'est pas en train d'utiliser une capacit\195\169 : %s"
L["BlockerMaterials"] = "Poss\195\168de suffisamment de mat\195\169riaux : %s"
L["BlockerInventory"] = "Poss\195\168de suffisamment d'espace dans l'inventaire : %s"
