-- busted helper: runs before every spec file. Tests run on Lua 5.1, the same
-- dialect as the WoW client.
package.path = "./?.lua;./?/init.lua;" .. package.path
