using ..Registrator: decodeb64

function is_pfile_parseable(c::AbstractString)
    @debug("Checking whether Project.toml is non-empty and parseable")
    if length(c) != 0
        try
            TOML.parse(c)
            return true, nothing
        catch ex
            if isa(ex, CompositeException) && isa(ex.exceptions[1], TOML.ParserError)
                err = "Error parsing project file"
                @debug(err)
                return false, err
            else
                rethrow(ex)
            end
        end
    else
        err = "Project file is empty"
        @debug(err)
        return false, err
    end
end

function is_pfile_nuv(c)
    @debug("Checking whether Project.toml contains name, uuid and version")
    ib = IOBuffer(c)

    try
        p = Pkg.Types.read_project(copy(ib))
        if p.name === nothing || p.uuid === nothing || p.version === nothing
            err = "Project file should contain name, uuid and version"
            @debug(err)
            return false, err
        elseif !isempty(p.version.prerelease)
            err = "Pre-release version not allowed"
            @debug(err)
            return false, err
        elseif p.version == v"0"
            err = "Package version must be greater than 0.0.0"
            @debug(err)
            return false, err
        end
    catch ex
        err = "Error reading Project.toml: $(ex.msg)"
        @debug(err)
        return false, err
    end

    return true, nothing
end

function is_pfile_valid(c::AbstractString)
    for f in [is_pfile_parseable, is_pfile_nuv]
        v, err = f(c)
        v || return v, err
    end
    return true, nothing
end

function verify_projectfile_from_sha(reponame, sha; auth=GitHub.AnonymousAuth())
    projectfile_contents = nothing
    projectfile_found = false
    projectfile_valid = false
    err = nothing
    @debug("Getting gitcommit object for sha")
    gcom = gitcommit(reponame, GitCommit(Dict("sha"=>sha)); auth=auth)
    @debug("Getting tree object for sha")
    t = tree(reponame, Tree(gcom.tree); auth=auth)

    for tr in t.tree
        if tr["path"] == "Project.toml"
            projectfile_found = true
            @debug("Project file found")

            @debug("Getting projectfile blob")
            if isa(auth, GitHub.AnonymousAuth)
                a = get_user_auth()
            else
                a = auth
            end
            b = blob(reponame, Blob(tr["sha"]); auth=a)

            @debug("Decoding base64 projectfile contents")
            projectfile_contents = decodeb64(b.content)

            @debug("Checking project file validity")
            projectfile_valid, err = is_pfile_valid(projectfile_contents)
            break
        end
    end

    return projectfile_contents, t.sha, projectfile_found, projectfile_valid, err
end
