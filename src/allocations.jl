function alloc_check(
    title, dependencies, targets, pre_alloc, alloc; path=pwd(), labeller=:version
)
    @info "Tracking allocations: $title"

    # cd to path if valid
    isdir(path) && cd(path)

    # add a proc (id == p) that track allocations
    p = first(addprocs(1; exeflags=["--track-allocation=user", "--project=$path"]))

    @eval @everywhere $p using Pkg
    @eval @everywhere $p Pkg.instantiate()
    @eval @everywhere $p using Profile

    # @info read("Project.toml", String)
    # @warn read("Manifest.toml", String)

    for d in dependencies
        @eval @everywhere $p using $(Symbol(d))
    end

    @eval @everywhere $p $pre_alloc()
    @eval @everywhere $p Profile.clear_malloc_data()
    @eval @everywhere $p $alloc()

    rmprocs(p)

    myallocs = Coverage.analyze_malloc(map(dirname ∘ pathof ∘ eval, targets))

    for t in targets, d in walkdir(dirname(pathof(t))), f in d[end]
        splitext(f)[2] == ".mem" && rm(joinpath(d[1], f))
    end
    for d in walkdir(path), f in d[end]
        splitext(f)[2] == ".mem" && rm(joinpath(d[1], f))
    end

    # Smart paths
    common, specifics = smart_paths(map(a -> a.filename, Iterators.reverse(myallocs)))
    # @info "sizes" map(a -> a.filename, Iterators.reverse(myallocs)) specifics
    slash = Sys.iswindows() ? "\\" : "/"

    # Make the allocations data readable through a dataframe
    df = DataFrame()
    df.bytes = map(a -> a.bytes, Iterators.reverse(myallocs))
    df[!, "ratio (%)"] = round.(df.bytes / sum(df.bytes) * 100; digits=2)
    df[!, "filename: [$common$slash"] = map(first ∘ splitext ∘ first ∘ splitext, specifics)
    df.linenumber = map(a -> a.linenumber, Iterators.reverse(myallocs))

    # Save it as a CSV file
    label = ""
    if labeller == :oid
        label = oid2string(map(p -> joinpath(dirname(pathof(p)), ".."), targets))
    elseif labeller == :version
        label = version2string(map(p -> joinpath(dirname(pathof(p)), ".."), targets))
    end
    mkpath("mallocs")
    CSV.write(joinpath(path, "mallocs/mallocs$label.csv"), df)

    # Visualize a pretty table
    pretty_table(df)

    return nothing
end

function pie_filter(df, threshold=5.0)
    i = findfirst(x -> x < threshold, df[!, 2])
    X = df[1:(i - 1), 3] .* " line " .* map(string, df[1:(i - 1), 4])
    push!(X, "others .< $threshold")
    Y = df[1:(i - 1), 2]
    push!(Y, sum(df[i:end, 2]))
    return X, Y
end

function alloc_plot(targets; formats=["pdf", "tikz", "svg", "png"], backend=pgfplotsx)
    backend()
    for target in targets
        path = normpath(joinpath(dirname(pathof(target)), "..", "perf", "mallocs"))
        versions = Vector{VersionNumber}()
        for f in readdir(path; join=true)
            st = splitext(basename(f))
            last(st) == ".csv" || continue
            push!(versions, VersionNumber(first(st)[9:end]))
        end
        sort!(versions)

        bytes = Vector{Int}()
        for version in versions
            csv_path = joinpath(path, "mallocs-$(string(version)).csv")
            df = DataFrame(CSV.File(csv_path))
            push!(bytes, sum(df.bytes))

            X, Y = pie_filter(df)
            pie(X, Y; title="Mallocs for $target.jl@v$(string(version))", l=0.5)
            for format in formats
                savefig(joinpath(path, "mallocs-$version.$format"))
            end
        end
        plot(
            map(string, versions),
            bytes;
            xlabel="version",
            ylabel="bytes",
            markershape=:circle,
            seriestype=:step,
            title="Mallocs evolution in\n$target.jl",
            l=0.5,
        )
        for format in formats
            savefig(joinpath(path, "mallocs-evolutions.$format"))
        end
    end
end
