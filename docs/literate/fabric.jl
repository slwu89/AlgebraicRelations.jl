# # Data Fabric
using Catlab
using ACSets
using AlgebraicRelations
# "SQLACSets" refers to data sources, specifically relational databases, which implement the ACSet interface. The trivial
# example of this case is the ACSet, which is an in-memory database. However, we can also implement the ACSet interface for a SQLite connection. Since anything can implement the ACSet interface, we're interested in a structure which can dispatch ACSet methods over the right datasource. This distributed architecture is a valuable practice in enterprise database administration for unifying data which might be maintained by their product owner and accessed through microservices. It provides a unified access protocol and a virtualization layer where data from data sources are cached for quicker retrieval. An object which catalogs where data resides makes its retrieval and collation easier to specify, maintain, and, by cacheing data in memory, faster. This "data fabric" is business jargon, but satisfactorily evokes a feeling of cohesion among variegated data.

# We have implemented a data fabric without the virtualization layer. That is, we do
# not load data from our data sources into memory as a unified schema.
# Currently, we rely on our **catalog** to both direct us to the right database
# connection for our query as well as keep a record of the available
# information. But as we transition into loading subsets of data into memory,
# it's worthwhile to explore whether a separate graph-like object would be
# responsible for retaining the actual queried data.

# An already-existing distinction in AlgebraicJulia is that between
# a presentation of a schema and its instantiation.

# We will assume we have a list of students schematized...
@present SchStudent(FreeSchema) begin
    Name::AttrType
    Student::Ob
    name::Attr(Student, Name)
end
@acset_type Student(SchStudent)
students_acset = InMemory(Student{Symbol}())

# ...and their classes...
@present SchClass(FreeSchema) begin
    Name::AttrType
    Class::Ob
    subject::Attr(Class, Name)
end
@acset_type Class(SchClass)
classes = Class{Symbol}()

using SQLite, DBInterface
class_db = DBSource(SQLite.DB(), acset_schema(classes))
execute!(class_db, "create table `Class` (_id int, subject varchar(255))")

# ...but they are stored in different data sources. Let's suppose we have
# a many-many relationship of students and classes. Here is their membership:
df = Dict(:Fiona => [:Math, :Philosophy, :Music],
          :Gregorio => [:Cooking, :Math, :CompSci],
          :Heather => [:Gym, :Art, :Music, :Math])

# Let's construct an example where the students and class information is stored
# elsewehere and the membership is currently unknown. We'll add students...
add_parts!(students_acset, :Student, length(keys(df)), name=keys(df))

subpart(students_acset.value, :name)

# ...and classes...
execute!(class_db,
    """insert or ignore into `class` (_id, subject) values
    (1, "Math"), (2, "Philosophy"), (3, "Music"),
    (4, "Cooking"), (5, "CompSci"), (6, "Gym"), (7, "Art")
    """)
subpart(class_db, :class) # TODO notice how we don't query by column. 

# We will reconcile them locally with a junction table that has a reference to them, schematized as simply a "Junction" object. Since we are not yet ready to add constraints to both Student and Class, the Junction schema--essentially a table of just references--is very plain.
@present SchSpan(FreeSchema) begin
    Id::AttrType
    Junction::Ob
    class::Attr(Junction, Id)
    student::Attr(Junction, Id)
end
@acset_type JunctionStudentClass(SchSpan)

junction_acset = InMemory(JunctionStudentClass{Int}())

# In the meantime, let's invoke our data fabric.
fabric = DataFabric()

# We'll gradually adapt this example to different kinds of data sources, but
# for the time being we'll consider both student and class tables as
# in-memory data sources.
add_source!(fabric, students_acset)
add_source!(fabric, class_db)
add_source!(fabric, junction_acset)

add_fk!(fabric, 3, 1, :Junction!student => :Student!Student_id)
add_fk!(fabric, 3, 2, :Junction!class => :Class!Class_id)

# The DSG describes three data sources with two constraints. 
fabric.graph

# Whether the constraints are valid is not yet enforced...they're just something we the users assert. To assure ourselves that this schema makes sense, we should be able to adapt our `join` method from Catlab to recobble the familiar Student-Class junction example. Because the data fabric presents a unified access layer for data, we'd need a catalog of available schema to find the information we need. In database science, reflection is the ability for databases to store information about their own schema. The fact that information about a database schema can also be represented as a schema is more plainly attributed to the mathematical formalism of schemas as attributed C-Sets. So naturally we implemented `reflect` for the data fabric:
reflect!(fabric)

# Let's query the names of the students and the available classes. The names of
# the students are stored in-memory:
subpart(fabric, :name)
# TODO this must fail if the catalog is empty

# Meanwhile the available subjects are stored in a SQLite database. We query
# them as if they were an ACSet.
subpart(fabric, :subject)

# What are the ID
incident(fabric, :Philosophy, :subject)

incident(fabric, :Heather, :name)

function Base.insert!(fabric::DataFabric, df::Dict{Symbol, Vector{Symbol}})
  foreach(keys(df)) do student
      classes = df[student]
      student_id = incident(fabric, student, :name)
      foreach(classes) do class
          class_id = incident(fabric, class, :subject)._id
          # not idempotent
          add_part!(fabric, :Junction, student=first(student_id), class=first(class_id))
      end
  end
  fabric
end

insert!(fabric, df)

subpart(fabric, :student)
subpart(fabric, :name)

subpart(fabric, :class)
subpart(fabric, :subject)
