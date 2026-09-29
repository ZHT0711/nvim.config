-- Route network access from Neovim-spawned processes (curl / wget used by
-- lazy.nvim, mason.nvim, nvim-treesitter, blink.cmp, ...) through the local
-- proxy, otherwise downloads from github.com time out.
vim.env.http_proxy = "http://127.0.0.1:7897"
vim.env.https_proxy = "http://127.0.0.1:7897"
vim.env.HTTP_PROXY = "http://127.0.0.1:7897"
vim.env.HTTPS_PROXY = "http://127.0.0.1:7897"

-- Piped Python stdout defaults to the ANSI codepage (GBK on zh-CN Windows),
-- which F9 output showed as <c4><e4><b2><d8> byte placeholders in the
-- quickfix list. Force UTF-8 stdio for anything nvim spawns; open() keeps
-- its locale default, so scripts reading GBK files are unaffected.
vim.env.PYTHONIOENCODING = "utf-8"

-- ============================ Shell =============================
--
-- Pin 'shell' to Git Bash. nvim 0.12 only picks bash when the launching
-- process's PATH contains bash.exe: from a terminal that holds, but a nvim
-- started from the Start menu falls back to cmd.exe, whose AutoRun conda
-- hook (a DOSKEY macro) dies with `拒绝访问` + exit 1 under :terminal,
-- leaving an empty dead buffer.
--
-- 'shell' must stay free of spaces: :terminal validates the first word
-- verbatim and E475s on "D:/Program". So add Git's bin dir to nvim's own
-- PATH and reference the interpreter by its bare name instead.
local git_bin = "D:/Program Files/Git/bin"
if vim.uv.fs_stat(git_bin .. "/bash.exe") then
    vim.env.PATH = git_bin .. ";" .. vim.env.PATH
    vim.o.shell = "bash.exe"
end

-- Neovim derives 'shell' from $SHELL (Git Bash here) but keeps cmd.exe-style
-- defaults for the companion options, so every shell-string call (:make, :!,
-- vim.fn.system) fails with `bash: /s: No such file or directory`. Only
-- realign the options when the shell actually is sh-like; cmd.exe users keep
-- the stock defaults.
local shell_name = vim.fn.fnamemodify(vim.o.shell, ":t"):lower()
if not shell_name:match "^cmd" and vim.o.shellcmdflag:find "/c" then
    vim.o.shellcmdflag = "-c"
    vim.o.shellxquote = ""
end

-- ============================ C / C++ ============================

-- clangd is the syntax checker (LSP diagnostics) for c/cpp buffers.
--
-- --query-driver makes clangd probe gcc/g++ for their include paths; without
-- it clangd cannot find the MSYS2 headers and every #include reports
-- "file not found".
--
-- The cmd is registered explicitly so the clangd already on PATH works from
-- the very first launch; `enabled = true` additionally lets Mason install a
-- managed copy (blink.cmp completion capabilities are attached by Mason on
-- the run after that install finishes).
local clangd_cmd = {
    "clangd",
    "--query-driver=C:/msys64/ucrt64/bin/gcc.exe,C:/msys64/ucrt64/bin/g++.exe",
}
Ice.lsp.clangd.enabled = true
Ice.lsp.clangd.setup = { cmd = clangd_cmd }
vim.lsp.config("clangd", { cmd = clangd_cmd })

-- gcc/g++ are the default compilers: <F9> runs :make on the current file and
-- loads compiler errors/warnings into the quickfix list (gcc.vim provides the
-- errorformat; it does not set 'makeprg' itself).
Ice.ft:set("c", function()
    vim.cmd "compiler gcc"
    vim.bo.makeprg = 'gcc -Wall "%"'
    vim.keymap.set("n", "<F9>", ":silent make | copen<CR>", { buffer = 0, desc = "compile with gcc" })
end)

Ice.ft:set("cpp", function()
    vim.cmd "compiler gcc"
    vim.bo.makeprg = 'g++ -Wall "%"'
    vim.keymap.set("n", "<F9>", ":silent make | copen<CR>", { buffer = 0, desc = "compile with g++" })
end)

-- ============================ Python / Go ============================
--
-- Enables the entries already declared in lsp/lsp.lua. Mason installs the
-- servers plus their `formatter` fields (black / gofumpt), which null-ls
-- picks up automatically for <leader>lf. The LSPs attach from the first nvim
-- start AFTER the Mason install has finished.
Ice.lsp.pyright.enabled = true
Ice.lsp.gopls.enabled = true

-- Neovim 0.12 removed compiler/python.vim, so the stock Ice.ft.python callback
-- dies with E666 on every .py open and its <F9> mapping never gets set.
-- Replace it wholesale, keeping the original intent: <F9> runs the script and
-- maps "File ... line ..." traceback frames into the quickfix list.
Ice.ft.python = function()
    vim.bo.formatoptions = "tcqjor"
    vim.wo.colorcolumn = "88"
    -- F9 interpreter: buffer-local b:python_exe > session-wide g:python_exe
    -- (set by the :PyEnv command below) > the conda "yolo" env as default.
    -- A conda env needs no activation: its python.exe carries its own
    -- site-packages, and :make's fresh shell never sees `conda activate`.
    local py_exe = vim.b.python_exe or vim.g.python_exe or "D:/miniconda3/envs/yolo/python.exe"
    vim.bo.makeprg = py_exe .. ' "%"'
    -- Commas inside an efm pattern separate alternatives; escape them as \,
    -- otherwise the pattern is silently split into garbage.
    vim.bo.errorformat = table.concat({
        '  File "%f"\\, line %l\\, in %m',
        '  File "%f"\\, line %l',
        '%-GTraceback (most recent call last):',
        -- '+G' keeps every remaining line (the final "XXXError: ..." line and
        -- the script's own print output) as quickfix entries; '-G' drops them,
        -- which hides the actual error message.
        '%+G%.%#',
    }, ",")
    vim.keymap.set("n", "<F9>", ":silent make | copen<CR>", { buffer = 0, desc = "run python" })
end

-- :PyEnv <name> points F9 at that conda env's interpreter for the whole
-- session (<Tab> completes env names); with no argument it restores the
-- "yolo" default. Applies to every python buffer, open ones included.
vim.api.nvim_create_user_command("PyEnv", function(opts)
    local envs_root = "D:/miniconda3/envs/"
    local py_exe
    if opts.args ~= "" then
        if vim.fn.isdirectory(envs_root .. opts.args) == 0 then
            vim.notify("No conda env named '" .. opts.args .. "' in " .. envs_root, vim.log.levels.ERROR)
            return
        end
        py_exe = envs_root .. opts.args .. "/python.exe"
    end
    vim.g.python_exe = py_exe
    local resolved = py_exe or "D:/miniconda3/envs/yolo/python.exe"
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].filetype == "python" then
            vim.bo[buf].makeprg = resolved .. ' "%"'
        end
    end
    vim.notify("F9 now runs " .. resolved)
end, {
    nargs = "?",
    complete = function()
        local names = {}
        for name, ftype in vim.fs.dir "D:/miniconda3/envs" do
            if ftype == "directory" then
                names[#names + 1] = name
            end
        end
        return names
    end,
})

-- ======================= 浏览器式缓冲区标签页 =======================
--
-- IceNvim removed bufferline and forced 'showtabline' off (see the comment
-- in core/basic.lua); this restores the browser-like buffer tabs from the
-- old screenshots.
vim.opt.showtabline = 2

Ice.plugins.bufferline = {
    "akinsho/bufferline.nvim",
    event = "User IceAfter colorscheme",
    dependencies = { "nvim-web-devicons" },
    opts = {
        options = {
            mode = "buffers",
            diagnostics = "nvim_lsp",
            -- bufferline's own auto-toggle only counts buffers and would
            -- resurface the bar inside splits; the custom toggle below owns
            -- 'showtabline' instead.
            auto_toggle_bufferline = false,
        },
    },
    keys = {
        { "<Tab>", "<Cmd>BufferLineCycleNext<CR>", desc = "tab next" },
        { "<S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", desc = "tab prev" },
        { "<leader>bp", "<Cmd>BufferLinePick<CR>", desc = "tab pick" },
        -- NOT <leader>bd: core/keymap.lua owns that as "close this buffer"
        -- and lazy registers these keys after group_map, which would shadow it.
        { "<leader>bx", "<Cmd>BufferLinePickClose<CR>", desc = "tab pick close" },
    },
}

-- Tab bar visibility: show only in a full-screen layout with more than one
-- buffer open (>1 buffer AND zero split windows in the current tab). Splits
-- are temporary side-by-side views and must keep the bar hidden.
--
-- Updates are deferred with vim.schedule so they land after other plugins'
-- synchronous showtabline writes (dashboard restore, lualine setup, ...) in
-- the same event tick, making this the last writer.
local pending_tabbar_update = false
local function tabbar_update()
    if pending_tabbar_update then
        return
    end
    pending_tabbar_update = true
    vim.schedule(function()
        pending_tabbar_update = false
        if vim.bo.filetype == "dashboard" then
            return -- the dashboard owns 'showtabline' while it is open
        end
        local bufs = #vim.fn.getbufinfo { buflisted = 1 }
        -- Real windows only: nvim-scrollview hangs a focusable=false float
        -- (relative ~= "") on every window, which would otherwise make every
        -- full-screen layout look like a split and keep the bar hidden.
        local wins = 0
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_config(win).relative == "" then
                wins = wins + 1
            end
        end
        vim.o.showtabline = (bufs > 1 and wins == 1) and 2 or 0
    end)
end

local tabbar_group = vim.api.nvim_create_augroup("IceTabbar", { clear = true })
for _, event in ipairs {
    "VimEnter",
    "BufAdd",
    "BufDelete",
    "BufWipeout",
    "BufEnter",
    "WinNew",
    "WinClosed",
    "TabNew",
    "TabClosed",
} do
    vim.api.nvim_create_autocmd(event, { group = tabbar_group, callback = tabbar_update })
end
tabbar_update()

-- ===================== telescope fzf 排序扩展 =====================
--
-- The stock build task drives cmake with the Visual Studio generator and
-- never produced build/libfzf.dll here, so `load_extension "fzf"` aborted
-- telescope's config on every start. fzf_lib.lua FFI-loads exactly
-- <plugin>/build/libfzf.dll, which the plugin's own Makefile builds with a
-- single gcc call — pin that instead (absolute path: gcc lives in the msys
-- tree, not necessarily in the PATH nvim is started with).
for _, dep in ipairs(Ice.plugins.telescope.dependencies) do
    if type(dep) == "table" and type(dep[1]) == "string" and dep[1]:find "fzf%-native" then
        dep.build =
            "C:/msys64/ucrt64/bin/gcc.exe -O3 -Wall -fpic -std=gnu99 -shared src/fzf.c -o build/libfzf.dll"
    end
end
