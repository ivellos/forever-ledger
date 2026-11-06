-- Hidden ("secret") event text never reaches the handlers.
local T = ...
local ns = T.ns

T.test("Hidden event text: hidden message skipped and counted, other hidden arguments are nil", function()
  local heard, got = 0, nil
  ns:On("FL_TEST_SECRET", function(a, b) heard = heard + 1; got = { a, b } end)
  for _, f in ipairs(T.S.frames) do
    if f.events.FL_TEST_SECRET then
      issecretvalue = function(v) return v == "hidden" end
      f.scripts.OnEvent(f, "FL_TEST_SECRET", "plain", 1, nil)
      f.scripts.OnEvent(f, "FL_TEST_SECRET", "hidden", 1)
      T.eq(heard, 1)
      f.scripts.OnEvent(f, "FL_TEST_SECRET", "plain", "hidden")
      issecretvalue = nil
    end
  end
  T.eq(heard, 2)
  T.eq(got[1], "plain")
  T.eq(got[2], nil)
  T.eq(ns.secretSkipped.FL_TEST_SECRET, 1)
end)
