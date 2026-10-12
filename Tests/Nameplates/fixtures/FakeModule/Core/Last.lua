local _, ns = ...

table.insert(ns.order, 'Last')
ns.card = CreateFrame('Frame', nil, UIParent, 'FakeModuleCardTemplate')
