local T = ...
local ns, S = T.ns, T.S
local Q = ns.buyQueueState
local function entry(id, price, value, quantity)
  return { id = id, cost = price, worth = value, limit = value - 1, n = quantity or 1,
    profit = (value - price) * (quantity or 1), lane = "flips", reason = "flip" }
end
local function setup(list, records, money, mode)
  ns.db.prices[ns.MarketKey()] = records or {}
  ns.db.settings.keepGold = 0
  ns.db.settings.buyQueue.limit, ns.db.settings.buyQueue.flipSort = nil, mode
  Q.lanes.flips, Q.spent, Q.lateBuys = list, 0, {}
  Q.state, Q.cur, Q.plan, Q.lastPlan, Q.buyFrom = "idle", nil, nil, nil, nil
  S.money = money or 10000
end
T.test("ROI: the unconfigured default still prioritizes affordable total profit", function()
  local large, efficient = entry(99011, 9000, 10000), entry(99012, 1000, 1500)
  setup({efficient, large})
  Q.sortFlips()
  T.eq(Q.lanes.flips[1], large)
end)
T.test("ROI: the selected mode prioritizes return on purchase cost", function()
  local large, efficient = entry(99011, 9000, 10000), entry(99012, 1000, 1500)
  setup({large, efficient}, nil, 10000, "roi")
  Q.sortFlips()
  T.eq(Q.lanes.flips[1], efficient)
  T.eq(efficient.roi, 0.5)
  T.eq(efficient.affordProfit, 500)
end)
T.test("ROI: unaffordable high returns stay behind purchasable entries", function()
  local poor, ready = entry(99011, 10001, 90000), entry(99012, 100, 120)
  setup({poor, ready}, nil, 10000, "roi")
  Q.sortFlips()
  T.eq(Q.lanes.flips[1], ready)
  T.eq(poor.affordN, 0)
end)
T.test("ROI: price depth uses cheap units before unaffordable expensive units", function()
  local e = entry(99011, 88, 100, 102)
  setup({e}, {[99011]={m=10,l="10:2,90:102"}}, 20, "roi")
  local q,c,p,r = Q.flipMetrics(e,20)
  T.eq(q,2);T.eq(c,20);T.eq(p,180);T.eq(r,9)
end)
T.test("ROI: cumulative ladder counts and partial affordability agree", function()
  local e = entry(99011, 25, 100, 8)
  setup({e}, {[99011]={m=10,l="10:2,25:5,40:8"}}, 110, "roi")
  local q,c,p,r = Q.flipMetrics(e,110)
  T.eq(q,5);T.eq(c,95);T.eq(p,405);T.eq(r,405/95)
end)
T.test("ROI: neither the price ceiling nor known quantity is exceeded", function()
  local e = entry(99011, 10, 100, 8)
  e.limit=20
  setup({e}, {[99011]={m=10,l="10:2,25:5,40:8"}}, 1000, "roi")
  local q,c = Q.flipMetrics(e,1000)
  T.eq(q,2);T.eq(c,20)
  e.n=1
  q,c=Q.flipMetrics(e,1000)
  T.eq(q,1);T.eq(c,10)
end)
T.test("ROI: reserve gold and remaining visit budget affect ranking quantities", function()
  local e=entry(99011,70,100,10)
  setup({e},nil,500,"roi")
  ns.db.settings.keepGold=100
  ns.db.settings.buyQueue.limit=80
  Q.spent=10
  Q.sortFlips()
  T.eq(e.affordN,1);T.eq(e.affordCost,70);T.eq(e.affordProfit,30)
  ns.db.settings.buyQueue.limit=nil
  Q.sortFlips()
  T.eq(e.affordN,5);T.eq(e.affordCost,350)
end)
T.test("ROI: fallback prices and exhausted budgets have defined results", function()
  local e=entry(99011,60,100,10)
  setup({e},nil,130,"roi")
  local q,c,p,r=Q.flipMetrics(e,130)
  T.eq(q,2);T.eq(c,120);T.eq(p,80);T.eq(r,80/120)
  q,c,p,r=Q.flipMetrics(e,0)
  T.eq(q,0);T.eq(c,0);T.eq(p,0);T.eq(r,nil)
end)
T.test("ROI: a scan showing nothing listed has no estimated purchasable profit", function()
  local e=entry(99011,60,100,10)
  setup({e},{[99011]={none=true}},1000,"roi")
  local q,c,p,r=Q.flipMetrics(e,1000)
  T.eq(q,0);T.eq(c,0);T.eq(p,0);T.eq(r,nil)
end)
T.test("ROI: equal returns use affordable profit and stable IDs", function()
  local a,b,c=entry(99011,100,150),entry(99012,200,300),entry(99013,200,300)
  setup({a,c,b},nil,10000,"roi")
  Q.sortFlips()
  T.eq(Q.lanes.flips[1],b);T.eq(Q.lanes.flips[2],c);T.eq(Q.lanes.flips[3],a)
end)
T.test("ROI: ranking does not change an in-flight quote or purchase limits", function()
  local e=entry(99011,60,100,10)
  setup({e},nil,1000,"roi")
  local plan={kind="commodity",qty=2,total=120}
  Q.cur,Q.plan,Q.state=e,plan,"confirm"
  Q.sortFlips()
  T.eq(Q.cur,e);T.eq(Q.plan,plan);T.eq(Q.state,"confirm");T.eq(e.limit,99)
  T.eq(plan.total,120);T.eq(plan.qty,2)
end)

T.test("ROI: explicitly watched items keep priority over profitable flips", function()
  local watch, flip = entry(99011, 100, 50), entry(99012, 10, 100)
  watch.reason, watch.limit = "watch", 100
  setup({flip, watch}, nil, 1000, "roi")
  Q.sortFlips()
  T.eq(Q.lanes.flips[1], watch)
  T.eq(watch.affordCost, 100)
  T.eq(watch.affordProfit, -50)
end)
