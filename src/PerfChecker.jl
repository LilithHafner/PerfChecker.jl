module PerfChecker

# SECTION - Imports
using Pkg
using Pkg.Types
import TOML: parse
using Profile
import TypedTables: Table
import Distributed: remotecall_fetch, addprocs, rmprocs
import CoverageTools: analyze_malloc_files, find_malloc_files, MallocInfo
import Base.Sys: CPUinfo, CPU_NAME, cpu_info, WORD_SIZE
import CpuId: simdbytes, cpucores, cpucores_total, cputhreads_per_core

struct HwInfo
    cpus::Vector{CPUinfo}
    machine::String
    word::Int
    simdbytes::Int
    corecount::Tuple{Int, Int, Int}
end

struct CheckerResult
    tables::Vector{Table}
    hwinfo::Union{HwInfo,Nothing}
    tags::Union{Nothing,Vector{Symbol}}
    pkgs::Vector{PackageSpec}
end

function Base.show(io::IO, v::PerfChecker.CheckerResult)
    println(io, "Tables:")
    for i in v.tables
        println(io, '\t', Base.display(i))
    end

    println(io, "Hardware Info:")
    println(io, "CPU Information:")
    println(io, '\t', v.hwinfo.cpus)
    println(io, "Machine name: ", v.hwinfo.machine)
    println(io, "Word Size: ", v.hwinfo.word)
    println(io, "SIMD Bytes: ", v.hwinfo.simdbytes)
    println(io, "Core count (physical, total and threads per core): ", v.hwinfo.corecount)

    println(io, "Tags used: ", v.tags)

    println(io, "Package versions tested (if provided): ")
    println(io, Base.display(v.pkgs))
end

find_by_tags(tags::Vector{Symbol}, results::CheckerResult; exact_match = true) = findall(x -> exact_match ? (tags == x.tags) : (!isempty(x.tags ∩ tags)), results)

# SECTION - Exports
export @check
export to_table
export find_by_tags
export get_versions

# SECTION - Includes
include("versions.jl")
include("check.jl")
include("alloc.jl")

end
