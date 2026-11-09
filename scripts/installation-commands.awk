BEGIN {
    hierarchy[1] = "apt"
    hierarchy[2] = "extrepo"
    hierarchy[3] = "command"
    hierarchy[4] = "snap"
    hierarchy[5] = "brew"
    field_separator = "%%%"
}

NR > 1 {
    if ($1 == "command" || $1 == "snap") {
        source = $1
        $1 = ""
        deps[source] = deps[source] field_separator $0
        next
    }
    deps[$1] = deps[$1] field_separator $2
}

END {
    for (source in hierarchy) {
        src = hierarchy[source]
        commands = get_src_commands(src, deps[src])
        print commands
    }
}

function get_src_commands(source, deps) {
    switch (source) {
    case "apt":
        return get_apt_commands(deps)
    case "extrepo":
        return get_extrepo_commands(deps)
    case "snap":
        return get_snap_commands(deps)
    case "command":
        return get_commands(deps)
    case "brew":
        return get_brew_commands(deps)
    }
    return "echo '" $1 "is not a registered source'"
}

function get_apt_commands(deps, commands) {
    gsub(field_separator, " ", deps)
    commands = "apt update\napt install -y " deps
    return commands
}

function get_extrepo_commands(deps, commands, dependencies, apt_commands, apt_deps, i) {
    split(deps, dependencies, field_separator)
    for (dep in dependencies) {
        if (!dependencies[dep]) continue
        commands = commands "\nextrepo enable " dependencies[dep]
        commands = commands "\nextrepo update " dependencies[dep]
        apt_deps = apt_deps field_separator dependencies[dep]
    }
    apt_commands = get_apt_commands(apt_deps)
    return commands "\n" apt_commands
}

function get_snap_commands(deps, commands, arguments, i) {
    split(deps, arguments, field_separator)
    for (arg in arguments) {
        if (!arguments[arg]) continue
        commands = command "\n" "snap install " arguments[arg]
    }
    return commands
}

function get_commands(deps, commands, cmd_str) {
    split(deps, commands, field_separator)
    for (cmd in commands) {
        if (!commands[cmd]) continue
        cmd_str = cmd_str "\n" commands[cmd]
    }
    return cmd_str
}

function get_brew_commands(deps, commands) {
    if (!deps) return ""
    gsub(field_separator, " ", deps)
    return "/opt/linuxbrew/bin/brew install -y " deps
}

