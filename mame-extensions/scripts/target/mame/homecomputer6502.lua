-- license:MIT
-- copyright-holders:Dirk Grappendorf
---------------------------------------------------------------------------
--
--   homecomputer6502.lua
--
--   Minimal MAME subtarget: only the HomeComputer 6502 driver.
--   Build with: make SUBTARGET=homecomputer6502 -j<N>
--
---------------------------------------------------------------------------

CPUS["M6502"] = true

SOUNDS["SID6581"] = true

VIDEOS["HD44780"] = true

MACHINES["6522VIA"] = true
MACHINES["MOS6551"] = true
MACHINES["INPUT_MERGER"] = true



function createProjects_mame_homecomputer6502(_target, _subtarget)
	project ("mame_homecomputer6502")
	targetsubdir(_target .."_" .. _subtarget)
	kind (LIBTYPE)
	uuid (os.uuid("drv-mame-homecomputer6502"))
	addprojectflags()
	precompiledheaders_novs()

	includedirs {
		MAME_DIR .. "src/osd",
		MAME_DIR .. "src/emu",
		MAME_DIR .. "src/devices",
		MAME_DIR .. "src/mame/shared",
		MAME_DIR .. "src/lib",
		MAME_DIR .. "src/lib/util",
		MAME_DIR .. "3rdparty",
		GEN_DIR  .. "mame/layout",
	}

	files{
		MAME_DIR .. "src/mame/homecomputer6502/homecomputer6502.cpp",
		-- Slim RS232: port + pty + null_modem only. Do not set BUSES["RS232"]; that
		-- compiles every RS232 peripheral (terminals, extra CPUs) and breaks the link.
		MAME_DIR .. "src/devices/bus/rs232/rs232.cpp",
		MAME_DIR .. "src/devices/bus/rs232/rs232.h",
		MAME_DIR .. "src/devices/bus/rs232/pty.cpp",
		MAME_DIR .. "src/devices/bus/rs232/pty.h",
		MAME_DIR .. "src/devices/bus/rs232/null_modem.cpp",
		MAME_DIR .. "src/devices/bus/rs232/null_modem.h",
	}

	custombuildtask {
		layoutbuildtask("mame/layout", "homecomputer6502"),
	}
end

function linkProjects_mame_homecomputer6502(_target, _subtarget)
	links {
		"mame_homecomputer6502",
	}
end
