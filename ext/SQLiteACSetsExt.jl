module SQLiteACSetsExt

using ACSets

using SQLite
using DataFrames

# need to pass in user config
function AlgebraicRelations.reload!(vas::VirtualACSet{SQLite.Connection})
    conn = SQLite.db()
    vas.conn = FunSQL.DB(conn, catalog=reflect(conn))
end

tosql(::VirtualACSet{SQLite.Connection}, ::Type{<:Real}) = "REAL"
tosql(::VirtualACSet{SQLite.Connection}, ::Type{<:AbstractString}) = "TEXT"
tosql(::VirtualACSet{SQLite.Connection}, ::Type{<:Symbol}) = "TEXT"
tosql(::VirtualACSet{SQLite.Connection}, ::Type{<:Integer}) = "INTEGER"
tosql(::VirtualACSet{SQLite.Connection}, T::DataType) = error("$T is not supported in this SQLite implementation")
# value conversion
tosql(::VirtualACSet{SQLite.Connection}, ::Nothing) = "NULL"
tosql(::VirtualACSet{SQLite.Connection}, x::T) where T<:Number = x
tosql(::VirtualACSet{SQLite.Connection}, s::Symbol) = string(s)
tosql(::VirtualACSet{SQLite.Connection}, s::String) = "\'$s\'"
tosql(::VirtualACSet{SQLite.Connection}, x) = x

function FunSQL.render(vas::VirtualACSet{SQLite.Connection}, i::ACSetInsert)
    cols = join(columns(i.values), ", ")
    values = join(["($x)" for x ∈ tosql.(Ref(vas), i.values.vals; key=false)], ", ")
    "INSERT IGNORE INTO $(i.table) ($cols) VALUES $values ;"
end

function FunSQL.render(vas::VirtualACSet{SQLite.Connection}, u::ACSetUpdate) 
    cols = join(columns(u.values), ", ")
    wheres = !isnothing(u.wheres) ? render(vas, u.wheres) : ""
    "UPDATE $(u.table) SET $(tosql(vas, u.values)) " * wheres * ";"
end

# TODO might have to refactor so we can reuse code for show method
function FunSQL.render(vas::VirtualACSet{SQLite.Connection}, s::ACSetSelect)
    from = s.from isa Vector ? join(s.from, ", ") : s.from
    qty = render(vas, s.qty)
    join = !isnothing(s.join) ? render(vas, s.join) : " "
    wheres = !isnothing(s.wheres) ? render(vas, s.wheres) : ""
    "SELECT $qty FROM $from " * join * wheres * ";"
end

function FunSQL.render(vas::VirtualACSet{SQLite.Connection}, j::ACSetJoin)
    "$(j.type) JOIN $(j.table) ON $(render(vas, j.on))"
end

function FunSQL.render(vas::VirtualACSet{SQLite.Connection}, ons::Vector{SQLEquation})
    join(render.(Ref(vas), ons), " AND ")
end

function FunSQL.render(vas::VirtualACSet{SQLite.Connection}, eq::SQLEquation)
    "$(eq.lhs.first).$(eq.rhs.second) = $(eq.rhs.first).$(eq.rhs.second)"
end

function FunSQL.render(vas::VirtualACSet{SQLite.Connection}, qty::SQLSelectQuantity)
    @match qty begin
        ::SelectAll || ::SelectDistinct || ::SelectDistinctRow => "*"
        SelectColumns(cols) => join(render.(Ref(vas), cols), ", ")
    end
end

function FunSQL.render(::VirtualACSet{SQLite.Connection}, column::Union{Pair{Symbol, Symbol}, Symbol})
    @match column begin
        ::Pair{Symbol, Symbol} => "$(column.first).$(column.second)"
        _ => column
    end
end

# TODO
function FunSQL.render(::VirtualACSet{SQLite.Connection}, wheres::WhereClause)
    @match wheres begin
        WhereClause(op, d::Pair) => "WHERE $(d.first) $op ($(join(d.second, ", ")))"
        _ => wheres
    end
end

function FunSQL.render(vas::VirtualACSet, c::ACSetCreate)
    create_stmts = map(objects(c.schema)) do ob
        obattrs = attrs(c.schema; from=ob)
        "CREATE TABLE IF NOT EXISTS $(ob)(" * 
            join(filter(!isempty, ["_id INTEGER PRIMARY KEY",
                # column_name column_type
                join(map(homs(c.schema; from=ob)) do (col, src, tgt)
                       tgttype = tosql(vas, Int)
                       "$(col) $tgttype"
                end, ", "),
                join(map(obattrs) do (col, _, type)
                    # FIXME
                    "$(col) $(tosql(vas, subpart_type(vas.acsettype(), type)))" 
               end, ", ")]), ", ") * ");"
    end
    join(create_stmts, " ")
end

function FunSQL.render(vas::VirtualACSet{SQLite.Connection}, d::ACSetDelete)
    "DELETE FROM $(d.table) WHERE _id IN ($(join(d.ids, ",")))"
end

function FunSQL.render(::VirtualACSet{SQLite.Connection}, v::Values)
    "VALUES " * join(entuple(v), ", ") * ";"
end

function FunSQL.render(::VirtualACSet{SQLite.Connection}, a::ACSetAlter)
    "ALTER TABLE $(a.refdom) ADD CONSTRAINT fk_$(ref) FOREIGN KEY ($(a.ref)) REFERENCES $(a.refcodom)(_id); "
end

function FunSQL.render(::VirtualACSet{SQLite.Connection}, fkc::ForeignKeyChecks)
    "SET FOREIGN_KEY_CHECKS = $(Int(fkc.bool)) ;"
end

# convenience
function AlgebraicRelations.ForeignKeyChecks(vas::VirtualACSet{SQLite.Connection}, stmt::String)
    l, r = render.(Ref(conn), ForeignKeyChecks.([false, true]))
    wrap(stmt, l, r)
end

# overloading syntactical constructors 
function AlgebraicRelations.ACSetInsert(vas::VirtualACSet{SQLite.Connection}, acset::ACSet)
    map(objects(acset_schema(acset))) do ob
        ACSetInsert(vas, acset, ob)
    end
end

function AlgebraicRelations.ACSetInsert(vas::VirtualACSet{SQLite.Connection}, acset::ACSet, table::Symbol)
    cols = colnames(acset, table)
    vals = getrows(vas, acset, table)
    ACSetInsert(table, vals, nothing)
end

end
