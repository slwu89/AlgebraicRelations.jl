module Fabric

using ...Schemas
using ..SQLACSetSyntax

# The DataFabric is an edge-labeled graph of data sources and schema-schema interrelations
# which implements the ACSet interface. It may "virtualize" data by querying it
# into memory.
#
# ## Colimiting: 
# If all the data sources have known database schema, then we can assembly the
# data into a single ACSet schema.
using Catlab
using ACSets

using MLStyle: @match
using Dates
using DataFrames
using DBInterface
using FunSQL
using FunSQL: reflect
import FunSQL: render

using Reexport

# DATA SOURCES
abstract type AbstractDataSource end
export AbstractDataSource

function recatalog! end
export recatalog!

include("catalog.jl")
# Data Source Graph

# TODO move to Catlab. This is a labeled graph whose edges are also labeled
@present SchEnrichedGraph <: SchLabeledGraph begin
    Value::AttrType
    value::Attr(V, Value)
    EdgeLabel::AttrType
    edgelabel::Attr(E, EdgeLabel)
end
@acset_type DataSourceGraph(SchEnrichedGraph)

DataSourceGraph() = DataSourceGraph{DataType, AbstractDataSource, Pair{Symbol, Symbol}}()
export DataSourceGraph

# DataFabric
struct Log
    time::DateTime
    event
    Log(event::DataType) = new(Dates.now(), event)
end
export Log

@kwdef mutable struct DataFabric
    # this will store the connections, their schema, and values
    graph::DataSourceGraph = DataSourceGraph()
    catalog::Catalog = Catalog()
    log::Vector{Log} = Log[]
end
export DataFabric

""" accesses the catalog for an abstract data source """
function catalog end
export catalog

catalog(fabric::DataFabric) = fabric.catalog

"""
"""
function recatalog!(fabric::DataFabric)
    foreach(parts(fabric.graph, :V)) do i    
        fabric.graph[i, :value] = recatalog!(subpart(fabric.graph, i, :value))
    end
    fabric
end

# TODO don't want copy sources
# TODO need idempotence
function reflect!(fabric::DataFabric)
    foreach(parts(fabric.graph, :V)) do source_id
        source = subpart(fabric.graph, source_id, :value)
        schema = SQLSchema(Presentation(acset_schema(source)))
        add_to_catalog!(fabric.catalog, schema; source=source_id, conn=typeof(source))
    end
    # TODO improve this
    foreach(parts(fabric.graph, :E)) do edge_id
        src, tgt, edgelabel = subpart.(Ref(fabric.graph), edge_id, [:src, :tgt, :edgelabel])
        # gets table associated to source
        fromtable, fromcol = split("$(edgelabel.first)", "!")
        totable, tocol = split("$(edgelabel.second)", "!")
        from = only(incident(fabric.catalog, Symbol(fromcol), :cname))
        to = only(incident(fabric.catalog, Symbol(tocol), :cname))
        # check if it should be added
        check1 = incident(fabric.catalog, to, :to)
        check2 = incident(fabric.catalog, from, :from)
        if check1 == [] && check2 == []
            add_part!(fabric.catalog, :FK, to=to, from=from)
        end
    end
    catalog(fabric)
end
export reflect!

# Adding to the Fabric

function add_source!(fabric::DataFabric, source::AbstractDataSource)
    add_part!(fabric.graph, :V, value=source)
end
export add_source!

function add_table!(fabric::DataFabric, tname::Symbol, source_id::Int=1)
    add_part!(fabric.catalog, :Table, tname=gensym(), source_id=source_id)
end
export add_table!

function add_fk!(fabric::DataFabric, src::Int, tgt::Int, elabel::Pair{Symbol, Symbol})
    add_part!(fabric.graph, :E, src=src, tgt=tgt, edgelabel=elabel)
end
export add_fk!

# Executing commands on data fabric

""" """
function render end
export render

""" """
function execute!(fabric::DataFabric, source_id::Int, stmt)
    execute!(fabric.graph[source_id, :value], stmt)
    # recatalog!(fabric.catalog[source_id, :conn])
end
export execute!

include("acset_interface.jl")

include("datasources/database/DatabaseDS.jl")
include("datasources/inmemory/InMemoryDS.jl")

@reexport using .DatabaseDS
@reexport using .InMemoryDS


end
