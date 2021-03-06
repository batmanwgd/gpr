------------------------------------------------------------------------------
--                                                                          --
--                           GPR2 PROJECT MANAGER                           --
--                                                                          --
--                     Copyright (C) 2019-2020, AdaCore                     --
--                                                                          --
-- This is  free  software;  you can redistribute it and/or modify it under --
-- terms of the  GNU  General Public License as published by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for more details.  You should have received  a copy of the  GNU  --
-- General Public License distributed with GNAT; see file  COPYING. If not, --
-- see <http://www.gnu.org/licenses/>.                                      --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Characters.Handling;

with GPR2.Containers;
with GPR2.Project.Name_Values;
with GPR2.Project.Registry.Attribute;
with GPR2.Source_Reference.Identifier;
with GPR2.Source_Reference.Value;

package GPR2.Project.Attribute is

   use all type Registry.Attribute.Value_Kind;

   type Object is new Name_Values.Object with private;

   Undefined : constant Object;
   --  This constant is equal to any object declared without an explicit
   --  initializer.

   overriding function Is_Defined (Self : Object) return Boolean;
   --  Returns true if Self is defined

   function Create
     (Name    : Source_Reference.Identifier.Object;
      Index   : Source_Reference.Value.Object;
      Value   : Source_Reference.Value.Object;
      Default : Boolean) return Object
     with Post => Create'Result.Kind = Single
                  and then Create'Result.Name.Text = Name.Text
                  and then Create'Result.Count_Values = 1;
   --  Creates a single-valued object

   function Create
     (Name   : Source_Reference.Identifier.Object;
      Index  : Source_Reference.Value.Object;
      Value  : Source_Reference.Value.Object) return Object
     with Post => Create'Result.Kind = Single
                  and then Create'Result.Name.Text = Name.Text
                  and then Create'Result.Count_Values = 1;
   --  Creates a single-valued object with "at" number

   function Create
     (Name    : Source_Reference.Identifier.Object;
      Index   : Source_Reference.Value.Object;
      Values  : Containers.Source_Value_List;
      Default : Boolean := False) return Object
     with Post => Create'Result.Kind = List
                  and then Create'Result.Name.Text = Name.Text
                  and then Create'Result.Count_Values = Values.Length;
   --  Creates a multi-valued object

   overriding function Create
     (Name  : Source_Reference.Identifier.Object;
      Value : Source_Reference.Value.Object) return Object
     with Post => Create'Result.Kind = Single
                  and then Create'Result.Name.Text = Name.Text
                  and then Create'Result.Count_Values = 1;
   --  Creates a single-valued object

   function Create
     (Name    : Source_Reference.Identifier.Object;
      Value   : Source_Reference.Value.Object;
      Default : Boolean) return Object
     with Post => Create'Result.Kind = Single
                  and then Create'Result.Name.Text = Name.Text
                  and then Create'Result.Count_Values = 1;
   --  Creates a single-valued object with default flag

   overriding function Create
     (Name   : Source_Reference.Identifier.Object;
      Values : Containers.Source_Value_List) return Object
     with Post => Create'Result.Kind = List
                  and then Create'Result.Name.Text = Name.Text
                  and then Create'Result.Count_Values = Values.Length;
   --  Creates a multi-valued object

   function Create
     (Name    : Source_Reference.Identifier.Object;
      Values  : Containers.Source_Value_List;
      Default : Boolean) return Object
     with Post => Create'Result.Kind = List
                  and then Create'Result.Name.Text = Name.Text
                  and then Create'Result.Count_Values = Values.Length;
   --  Creates a multi-valued object with Default flag

   function Has_Index (Self : Object) return Boolean
     with Pre => Self.Is_Defined;
   --  Returns True if the attribute has an index

   function Index (Self : Object) return Source_Reference.Value.Object
     with Inline, Pre => Self.Is_Defined;
   --  Returns the attribute's index value

   function Index_Equal (Self : Object; Value : Value_Type) return Boolean
     with Pre => Self.Is_Defined and then Self.Has_Index;
   --  Returns True if the attribute's index is equal to Value taking into
   --  account the case-sensitivity of the index.

   function Is_Any_Index (Self : Object) return Boolean
     with Pre => Self.Is_Defined and then Self.Has_Index;
   --  Returns True if the attribute can be returned from the set for any
   --  index in a request. Main case to use such attributes is to get attribute
   --  with default value from the set when the default value defined for any
   --  index.

   procedure Set_Case
     (Self                    : in out Object;
      Index_Is_Case_Sensitive : Boolean;
      Value_Is_Case_Sensitive : Boolean)
     with Pre => Self.Is_Defined;
   --  Sets attribute case sensitivity for the index and the value.
   --  By default both are case-sensitive.

   overriding function Image
     (Self : Object; Name_Len : Natural := 0) return String
     with Pre => Self.Is_Defined;
   --  Returns a string representation. The attribute name is represented with
   --  Name_Len characters (right padding with space) except if Name_Len is 0.

   function Is_Default (Self : Object) return Boolean
     with Pre => Self.Is_Defined;
   --  Attribute did not exist in attribute set and was created from default
   --  value.

   overriding function Rename
     (Self : Object;
      Name : Source_Reference.Identifier.Object) return Object
     with Pre => Self.Is_Defined;
   --  Returns object with another name and default attribute

private

   type Value_At_Num (Length : Natural) is record
      Value  : Value_Type (1 .. Length);
      At_Num : Natural := 0;
   end record;

   function "<" (Left, Right : Value_At_Num) return Boolean is
     (Left.Value < Right.Value
      or else (Left.Value = Right.Value and then Left.At_Num < Right.At_Num));

   function Create (Value : Value_Type; At_Num : Natural) return Value_At_Num
   is ((Length => Value'Length, Value => Value, At_Num => At_Num));

   type Object is new Name_Values.Object with record
      Index                : Source_Reference.Value.Object;
      Index_Case_Sensitive : Boolean := True;
      Default              : Boolean := False;
   end record;

   function Case_Aware_Index (Self : Object) return Value_At_Num is
     (Create
        ((if Self.Index_Case_Sensitive
          then Self.Index.Text
          else Ada.Characters.Handling.To_Lower (Self.Index.Text)),
         At_Num_Or (Self.Index, 0)));
   --  Returns Index in lower case if index is case insensitive, returns as is
   --  otherwise.

   Undefined : constant Object := (Name_Values.Undefined with others => <>);

   function Is_Any_Index (Self : Object) return Boolean is
     (Self.Index_Equal (Any_Index));

   overriding function Is_Defined (Self : Object) return Boolean is
     (Self /= Undefined);

   function Is_Default (Self : Object) return Boolean is (Self.Default);

end GPR2.Project.Attribute;
