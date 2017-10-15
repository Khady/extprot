
This document assumes knowledge of the
[abstract syntax for protocol definition](protocol-definition.md).

## Learn by example

The protocol can be extended in several ways, a few of which are illustrated
in the following example. We'll be extending this trivial protocol definition:

    (* this is a comment (* and this a nested comment *) *)
    message user = {
      id : int;
      name : string;
    }

### New message fields

Suppose we find out some time later we also need the email and the age:

    message user = {
      id : int;
      name : string;
      email : string;
      age : int
    }

Adding new fields this way means that older readers can consume data from new
producers. If we also want new consumers to read old data, they have to cope
with the possibility that the new fields be missing, by using default values
for them (the easiest way to do so is to use disjoint unions, aka. sum types,
as explained below). For now, let's keep things simple.

### New tuple elements

Then we realize that all users have at least an email, but maybe more, so we
extend the message again:

    message user = {
      id : int;
      name : string;
      email : (string * [string]);  (* at least one email, maybe more *)
      age : int
    }

The email field is now a tuple with two elements, the first one being a
string, and the second one a list of strings that might be empty (in this
case, the user has got only one email).

### Disjoint unions (sum types)

Imagine our application has got several user types:

* free user
* paying user: we also want to record the end of the subscription period

This can be captured in the following type definition:

    type date = float (* time in seconds since the start of the epoch  *)

    type user_type = Free | Paying date
		            (* could be written as  Paying float *)

    message user = {
      id : int;
      name : string;
      emails : (string * [string]);  (* at least one email, maybe more *)
      age : int;
      user_type : user_type
    }

That's not all: we then decide that all users qualify for a discount rate one
time starting from now.

    (* whether we will offer a discount rate in the next renewal *)
    type discount = Yes | No

    type user_type = Free | Paying date discount

    (* same user definition as above *)

Old records of paying users have no discount element in their user_type field,
so the value will default to "Yes" when it is read by new consumers --- if we
wanted it to be "No" by default, we'd simply have to define the discount type
as

    type discount = No | Yes

### Polymorphic types

After a while, we have several message definitions, and realize that the "at
least one" pattern happens often. We can use a polymorphic type to avoid
having to type "(x * [x])" again and again:

    type one_or_more 'x = ('x * ['x])

    message user = {
      id : int;
      name : string;
      emails : one_or_more<string>;
      age : int;
      user_type : user_type;
    }

### Conbining polymorphism and sum types

Going back to the first extension we did, disjoint unions allow us to know when
a field is missing and to handle that case.

    type option 'a = None | Some 'a

    message user = {
      ...
      age : option<int>;
      ...
    }

This is no other than the option type from ML (Maybe in Haskell). A consumer
with the new type definition will know when a field is missing because the
value will be set to None. Refer to the documentation on the
[target language mappings](language-mapping.md) to see how this translates in
the target language.

## Primitive type expansion rule

The bool, byte, int, long, float and string types can be promoted to a tuple
or a sum type whose first non-constant constructor carries as its first
element a value of said primitive type.

Example:

    type dimension = int

can be extended to

    type variance = Unknown | Known int
    type dimension = (int * variance)

    (* alternatively *)

    type dimension = Dim int variance

The `Unknown` constructor in the `variance` type allows new readers to
deserialize old data, as missing variance fields/elements will default to
`Unknown`.

## Numeric type widening

Numeric types can be widened in the same way as in e.g. C, so

   type dimension = int

can be expanded later in time to

   type dimension = long

and newer readers will automatically expand old (int) data to the new (long)
type. At present, type narrowing is not supported, so older readers will not
be able to deserialize data that uses the new definition.

## Reference

We use this notation:

* original protocol definition: P
* extended protocol definition: P'
* node using P in consumer role: R
* node using P' in consumer role: R'
* node using P in producer role: W
* node using P' in producer role: W'

When *x* produces data that is consumed by *y*, we note x -> y.

Clearly,

    W  -> R
    W' -> R'

are supported for any non-broken protocol.

When W -> R' holds, we say the protocol is backward compatible (BC).

When W' -> R holds, we say the protocol is forward compatible (FC).

This table summarizes the extensions possible in extprot:

                                                                       BC   FC
    ----------------------------------------------------------------- ---- ----
     adding fields to messages or elements to tuples/constructor
         in general                                                         X
         fields/elements of type with default value                    X    X

     adding new constructor to sum type                                X

     adding new constructor to message                                 X

     extending primitive types to sum types, tuples or message

       ... and adding new elements
           general                                                          X
           new elements of type with default value                     X    X

       ... and adding new constructors                                 X

     numeric type widening                                             X

## Default values

The default value is defined for each type inductively: the default value of ...

* a sum type is its first constant contructor.
* a list is the empty list.
* an array is the empty array.
* a tuple is a tuple consisting of the default values of its types, if they
  are all defined.
* a message is the first message variant with the fields
  having the default values corresponding to their types, if they are all
  defined.
* a bool is `false`

Otherwise, the type/message has got no default value by default.

The default value for primitive types (bool, int, byte, long, float, string)
can be defined with the `option "default" = "..."` syntax when declaring a
type, or more conveniently with `[@default xxx]` which can be used directly in
any context where the primitive type can be used; e.g.


    type int_default_42 = int options "default" = "42"

    type int_42 = int [@default 42]

    message foo =
        { bar : int;
          i : int [@default 42];
          b : bool [@default true];
          s : string [@default "foo"];
          f : float [@default 3.14]
         }

### Examples

             type                                  default value
    ---------------------------------         ----------------------------------
     type bo = bool                            false

     type a = A int | B | C                    B

     type b = (a * a)                          (B, B)

     type c = [b]                              []       (empty list)

     type d = [|c|]                            [||]     (empty array)

     message m = { v1 : c; v2 : b }            { v1 = []; v2 = (B, B) }

     message n = { a : a; m : m }              { a = B;
                                                 m = { v1 = []; v2 = (B, B) } }

     message o = { a : a; b : bo }             { a = B; b = false }

     type id = int                             undefined
     type id2 = int options "default" = "4"    4
     type id2 = int [@default 42]              42

     type nodef1 = (a * int)                   undefined

     message p = { v : int }                   undefined

     message p = { v : int [@default 42] }     { v = 42 }

See the [target language documentation](language-mapping.md) for more
information about the mapping of the default value to the target language.
