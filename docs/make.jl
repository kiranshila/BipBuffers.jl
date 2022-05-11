using BipBuffers
using Documenter

DocMeta.setdocmeta!(BipBuffers, :DocTestSetup, :(using BipBuffers); recursive=true)

makedocs(;
    modules=[BipBuffers],
    authors="Kiran Shila <me@kiranshila.com> and contributors",
    repo="https://github.com/kiranshila/BipBuffers.jl/blob/{commit}{path}#{line}",
    sitename="BipBuffers.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://kiranshila.github.io/BipBuffers.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/kiranshila/BipBuffers.jl",
    devbranch="main",
)
