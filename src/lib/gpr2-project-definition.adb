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
with Ada.Containers.Doubly_Linked_Lists;
with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Strings.Maps.Constants;
with Ada.Text_IO;

with GNAT.MD5;
with GNAT.OS_Lib;

with GPR2.Unit;
with GPR2.Unit.List;
with GPR2.Message;
with GPR2.Path_Name.Set;
with GPR2.Project.Attribute;
with GPR2.Project.Registry.Attribute;
with GPR2.Project.Registry.Pack;
with GPR2.Project.Tree;
with GPR2.Source;
with GPR2.Source_Info.Parser.Registry;
with GPR2.Source_Reference.Identifier.Set;
with GPR2.Source_Reference.Value;

package body GPR2.Project.Definition is

   use GNAT;

   package PRA renames Project.Registry.Attribute;
   package PRP renames Project.Registry.Pack;

   Builtin_Naming_Package : Project.Pack.Object;
   --  The default naming package to use if no Naming package specified in the
   --  project and no configuration file loaded. We at least want to handle in
   --  this case the standard Ada and C namings.

   function Languages (Def : Data) return Containers.Source_Value_List is
     (Def.Attrs.Languages.Values);

   -------------------------------
   -- Check_Circular_References --
   -------------------------------

   function Check_Circular_References
     (View : Project.View.Object) return Boolean
   is

      Steps : Containers.Name_Set;
      Way   : Unbounded_String;

      procedure Next_View (From : Project.View.Object);
      --  Got to next level in check for reference circle

      ---------------
      -- Next_View --
      ---------------

      procedure Next_View (From : Project.View.Object) is
         Def  : constant Const_Ref := Get_RO (From);
         Name : constant Name_Type := From.Name;

         procedure Check_Relation
           (Dest : Project.View.Object; Kind : Name_Type)
           with Pre => Dest.Is_Defined;
         --  Check is the current step was not on the way

         --------------------
         -- Check_Relation --
         --------------------

         procedure Check_Relation
           (Dest : Project.View.Object;
            Kind : Name_Type)
         is
            Len : constant Natural := Length (Way);
            OK  : Boolean;
            CN  : Containers.Name_Type_Set.Cursor;

            function "&" (Left, Right : Name_Type) return Name_Type is
              (GPR2."&" (Left, Right));
            --  Workaround for GNAT visibility resolve error:
            --  ambiguous expression (cannot resolve "&")

            Point : constant Name_Type := Name & " " & Kind & " " & Dest.Name;
         begin
            Append (Way, String (Point) & "; ");
            Steps.Insert (Point, CN, OK);

            if not OK then
               raise Program_Error with
                 "references cycle: " & To_String (Way);
            end if;

            Next_View (Dest);
            Steps.Delete (Point);

            Delete (Way, Len + 1, Length (Way));
            pragma Assert (Length (Way) = Len);
         end Check_Relation;

      begin
         if Def.Extended.Is_Defined then
            Check_Relation (Def.Extended, "extended");
         end if;

         for V of Def.Imports loop
            Check_Relation (V, "import");
         end loop;

         for V of Def.Aggregated loop
            Check_Relation (V, "aggregated");
         end loop;
      end Next_View;

   begin
      Next_View (View);
      return True;
   end Check_Circular_References;

   --------------------
   -- Naming_Package --
   --------------------

   function Naming_Package (Def : Data) return Project.Pack.Object is
   begin
      if Def.Has_Packages (PRP.Naming) then
         return Def.Packs (PRP.Naming);

      elsif Def.Tree.Has_Configuration then
         return Def.Tree.Configuration.Corresponding_View.Naming_Package;

      else
         return Result : Project.Pack.Object := Builtin_Naming_Package do
            Definition.Set_Pack_Default_Attributes (Result, Def);
         end return;
      end if;
   end Naming_Package;

   ----------------------------
   -- Set_Default_Attributes --
   ----------------------------

   procedure Set_Default_Attributes (Def : in out Data) is

      procedure Inherite_Attribute (Name : Name_Type);
      --  Take attribute from extended project and put it inot current one
      --  if it exists in extended and is not defined in the current one.

      procedure Union_Attribute (Name : Name_Type);
      --  Union attribute values to the current project from the extended one

      ------------------------
      -- Inherite_Attribute --
      ------------------------

      procedure Inherite_Attribute (Name : Name_Type) is
         Attr : Attribute.Object;
      begin
         if not Def.Attrs.Contains (Name)
           and then Def.Extended.Check_Attribute (Name, Result => Attr)
         then
            Def.Attrs.Insert (Attr);
         end if;
      end Inherite_Attribute;

      ---------------------
      -- Union_Attribute --
      ---------------------

      procedure Union_Attribute (Name : Name_Type) is
         Parent : Attribute.Object;
         CT     : constant Attribute.Set.Cursor := Def.Attrs.Find (Name);
      begin
         if Def.Extended.Check_Attribute (Name, Result => Parent) then
            if Attribute.Set.Has_Element (CT) then
               for V of Parent.Values loop
                  if not Def.Attrs (CT).Has_Value (V.Text) then
                     Def.Attrs (CT).Append (V);
                  end if;
               end loop;

            else
               Def.Attrs.Insert (Parent);
            end if;
         end if;
      end Union_Attribute;

   begin
      if Def.Extended.Is_Defined then
         Union_Attribute (PRA.Languages);

         case Def.Kind is
            when K_Library | K_Aggregate_Library =>
               Inherite_Attribute (PRA.Library_Name);
            when K_Standard =>
               Inherite_Attribute (PRA.Main);
            when others =>
               null;
         end case;
      end if;

      Set_Defaults (Def.Attrs, Def, No_Name);

      for Pack of Def.Packs loop
         Definition.Set_Pack_Default_Attributes (Pack, Def);
      end loop;
   end Set_Default_Attributes;

   --------------------
   -- Update_Sources --
   --------------------

   procedure Update_Sources (Def : in out Data; View : Project.View.Object) is

      use type MD5.Binary_Message_Digest;
      use type Project.Attribute.Object;

      use GPR2.Containers;
      use GPR2.Path_Name;

      use type Source_Reference.Object;

      package Name_Boolean_Map is new Ada.Containers.Indefinite_Ordered_Maps
        (Name_Type, Boolean);

      package Unit_Name_To_Sloc is new
        Ada.Containers.Indefinite_Ordered_Maps
          (Name_Type, Source_Reference.Object);
      --  Used for the Interface_Units container which will initially store all
      --  the units from the Library_Interface attribute, as a mapping from
      --  unit names to slocs.

      package Source_Path_To_Sloc is new
        Ada.Containers.Indefinite_Ordered_Maps
          (Value_Type, Source_Reference.Object);
      --  Same as above but for the Interfaces attribute, so here we are using
      --  Value_Type instead of Name_Type since we're dealing with filenames.

      package Attribute_List is new
        Ada.Containers.Doubly_Linked_Lists (Project.Attribute.Object);
      --  Element type for Source_Path_To_Attribute_List below

      package Source_Path_To_Attribute_List is new
        Ada.Containers.Indefinite_Ordered_Maps
          (Key_Type     => Value_Type,
           Element_Type => Attribute_List.List,
           "="          => Attribute_List."=");
      --  Used for the Ada_Naming_Exceptions container which maps a filename to
      --  the list of naming attributes (Body/Spec) that reference it.

      package Naming_Exceptions_Usage is new
        Ada.Containers.Indefinite_Ordered_Maps
          (Key_Type     => Value_Type,
           Element_Type => Source_Reference.Value.Object,
           "="          => Source_Reference.Value."=");

      procedure Register_Units
        (Source : Project.Source.Object;
         Units  : Unit.List.Object)
        with Pre => Source.Source.Language = "Ada";
      --  Registers units for the given project source. Note that we need to
      --  pass the Units and not to use the one registered with the
      --  source as the later could have been updated by a real parser based on
      --  Libadalang for example. And in this case the units name could be non
      --  matching. This is true for the initial call in Handle_File.

      type Insert_Mode is (Skip, Error);
      --  Controls behavior when a duplicated unit/filename is found
      --
      --  Skip    : the new source is ignored
      --  Error   : an error is raised

      package Source_Set renames Containers.Value_Type_Set;

      procedure Handle_Directory (Dir : GPR2.Path_Name.Full_Name);
      --  Handle the specified directory, that is read all files in Dir and
      --  eventually call recursivelly Handle_Directory if a recursive read
      --  is specified.

      procedure Handle_File (Path : GPR2.Path_Name.Full_Name);
      --  Processes the given file: see if it should be added to the view's
      --  sources, and compute information such as language/unit(s)/...

      function Signature return MD5.Binary_Message_Digest;
      --  Compute the signature corresponding to the source context. If the
      --  signature is not the same recorded for the view, the source set
      --  need to be recomputed.

      procedure Read_File
        (Filename : GPR2.Path_Name.Full_Name;
         Set      : in out Source_Set.Set);
      --  Read Filename and insert each line in Set

      procedure Insert
        (Sources : Project.Source.Set.Object;
         Mode    : Insert_Mode;
         Sloc    : Source_Reference.Object'Class);
      --  Insert Sources from an extended or aggregated project into
      --  Def.Sources. Mode is Skip for extended projects (ignore sources from
      --  the extended project that have been replaced in the extending one),
      --  or Error for aggregated projects (reject duplicate sources).

      procedure Fill_Ada_Naming_Exceptions (Attr : Name_Type)
        with Pre => Attr in  PRA.Spec | PRA.Body_N;
      --  Fill the Ada_Naming_Exceptions object with the given attribute set

      procedure Fill_Other_Naming_Exceptions
        (Set : Project.Attribute.Set.Object)
        with Pre =>
          (for all A of Set =>
             A.Name.Text = PRA.Specification_Exceptions
             or else A.Name.Text = PRA.Implementation_Exceptions);

      function Is_Compilable (Language : Name_Type) return Boolean;
      --  Check whether the language is compilable on the current View. This
      --  includes information provided by the Tree (Driver attribute). Note
      --  that this routine caches the result into a map.

      Naming : constant Project.Pack.Object := Naming_Package (Def);
      --  Package Naming for the view

      Dot_Repl : constant String :=
                   Naming.Attribute (PRA.Dot_Replacement).Value.Text;
      --  Get Dot_Replacement value

      Is_Standard_GNAT_Naming : constant  Boolean :=
                                  (Naming.Spec_Suffix
                                       ("ada").Value.Text = ".ads")
                                     and then
                                  (Naming.Body_Suffix
                                       ("ada").Value.Text = ".adb")
                                     and then
                                  (Dot_Repl = "-");
      --  True if the current naming scheme is GNAT's default naming scheme.
      --  This is to take into account shortened names like "Ada." (a-),
      --  "System." (s-) and so on.

      Source_Dir_Ref    : Source_Reference.Object;

      Included_Sources  : Source_Set.Set;
      Excluded_Sources  : Source_Set.Set;

      Interface_Units       : Unit_Name_To_Sloc.Map;
      Interface_Units_Found : Name_Set;
      Interface_Found       : Boolean := False;
      Interface_Sources     : Source_Path_To_Sloc.Map;
      Language_Compilable   : Name_Boolean_Map.Map;
      Src_Dir_Set           : Source.Set.Object;
      --  Sources from one directory defined in one item of the Source_Dirs
      --  attribute. Need to avoid source duplications in Source_Dirs items
      --  containing '*' character.
      Has_Src_In_Lang       : Name_Set;
      --  Insert record there if the language has a source

      Tree                  : constant not null access Project.Tree.Object :=
                                Def.Tree;
      Message_Count         : constant Containers.Count_Type :=
                                Tree.Log_Messages.Count;

      Ada_Naming_Exceptions : Source_Path_To_Attribute_List.Map;
      Ada_Except_Usage      : Naming_Exceptions_Usage.Map;
      Other_Except_Usage    : Naming_Exceptions_Usage.Map;

      Visited_Dirs          : Containers.Value_Type_Set.Set;
      --  List of already visited directories to avoid looking twice at the
      --  same one.

      procedure Mark_Language (Lang : Name_Type);
      --  Mark that language exists in sources

      function Ada_Use_Index (Attr : Attribute.Object) return Value_Type is
        (Attr.Index.Text & Characters.Handling.To_Upper (Attr.Name.Text (1)));
      --  Index created from Body or Spec attribute index i.e. Ada unit name
      --  and first character of the attribute name i.e. B or S. It is used to
      --  distinct body naming exception from spec naming exception.

      --------------------------------
      -- Fill_Ada_Naming_Exceptions --
      --------------------------------

      procedure Fill_Ada_Naming_Exceptions (Attr : Name_Type) is
      begin
         for CA in Naming.Attributes.Iterate (Attr, With_Defaults => True) loop
            declare
               A               : constant Attribute.Object :=
                                   Attribute.Set.Element (CA);
               Source          : constant Value_Type := A.Value.Text;
               Attributes      : Attribute_List.List :=
                                   Attribute_List.Empty_List;
               Insert_Position : Source_Path_To_Attribute_List.Cursor;
               Is_Inserted     : Boolean;
            begin
               Attributes.Append (A);

               Ada_Naming_Exceptions.Insert
                 (Key      => Source,
                  New_Item => Attributes,
                  Position => Insert_Position,
                  Inserted => Is_Inserted);

               if not Is_Inserted then
                  Ada_Naming_Exceptions (Insert_Position).Append (A);
               end if;

               Ada_Except_Usage.Insert (Ada_Use_Index (A), A.Value);
            end;
         end loop;
      end Fill_Ada_Naming_Exceptions;

      ----------------------------------
      -- Fill_Other_Naming_Exceptions --
      ----------------------------------

      procedure Fill_Other_Naming_Exceptions
        (Set : Project.Attribute.Set.Object)
      is
         CE : Naming_Exceptions_Usage.Cursor;
         OK : Boolean;
      begin
         for A of Set loop
            for V of A.Values loop
               Other_Except_Usage.Insert (V.Text, V, CE, OK);

               if not OK then
                  Tree.Append_Message
                    (Message.Create
                       (Message.Error,
                        "File """ & V.Text
                        & """ specified in naming exception more than once",
                        V));
               end if;
            end loop;
         end loop;
      end Fill_Other_Naming_Exceptions;

      ----------------------
      -- Handle_Directory --
      ----------------------

      procedure Handle_Directory (Dir : GPR2.Path_Name.Full_Name) is
         use all type Directories.File_Kind;

         Is_Recursive : constant Boolean :=
                          Dir'Length > 2
                          and then Dir (Dir'Last) = '*'
                          and then Dir (Dir'Last - 1) = '*';
         --  Recursivity is controlled by a double * at the end of the
         --  directory.

         Dir_Name     : constant GPR2.Path_Name.Full_Name :=
                          (if Is_Recursive
                           then Dir (Dir'First .. Dir'Last - 2)
                           else Dir);
         Dir_Search   : Directories.Search_Type;
         Dir_Entry    : Directories.Directory_Entry_Type;
      begin
         if not Visited_Dirs.Contains (Dir) then
            Visited_Dirs.Insert (Dir);

            begin
               Directories.Start_Search (Dir_Search, Dir_Name, "*");
            exception
               when Ada.IO_Exceptions.Name_Error =>
                  Tree.Append_Message
                    (Message.Create
                       (Message.Error,
                        """" & Dir_Name & """ is not a valid directory",
                        Source_Dir_Ref));
            end;

            while Directories.More_Entries (Dir_Search) loop
               Directories.Get_Next_Entry (Dir_Search, Dir_Entry);

               if Directories.Kind (Dir_Entry) = Ordinary_File then
                  Handle_File (Directories.Full_Name (Dir_Entry));

               elsif Directories.Kind (Dir_Entry) = Directory
                 and then Is_Recursive
               then
                  Handle_Sub_Directory : declare
                     New_Dir : constant String :=
                                 Directories.Simple_Name (Dir_Entry);
                  begin
                     if New_Dir not in "." | ".." then
                        Handle_Directory (Directories.Full_Name (Dir_Entry));
                     end if;
                  end Handle_Sub_Directory;
               end if;
            end loop;

            Directories.End_Search (Dir_Search);
         end if;
      end Handle_Directory;

      -----------------
      -- Handle_File --
      -----------------

      procedure Handle_File (Path : GPR2.Path_Name.Full_Name) is
         use all type Unit.Kind_Type;

         --  The implementation works as follows:
         --    For every language L in the project:
         --      1- Check if F matches with a naming exception (see
         --         Check_Naming_Exceptions):
         --           - if L is Ada, look F up the Ada_Naming_Exceptions map
         --           - else, check the attributes Implementation_Exceptions
         --             and Specification_Exceptions for the language L.
         --             This was missing in the previous implementation.
         --           - This also computes Kind for non-Ada sources.
         --             For Ada sources we will compute a Kind for every
         --             compilation unit later on.
         --         If a match is found and L is Ada, then compute the
         --         compilation units.
         --      2- If no naming exceptions matched, check the naming scheme
         --         for L (see Check_Naming_Scheme):
         --           - Separate_Suffix is only checked for Ada.
         --           - This time, Kind is computed no matter the language, as
         --             for Ada we will assume the source is single-unit.
         --         If a match is found and L is Ada then compute the single
         --         compilation unit for the source. The unit name is derived
         --         from the file name (see Compute_Unit_From_Filename):
         --           - Validity checks on the unit name are only done here.
         --             Should this be reverted to the previous behavior, i.e.
         --             some checks apply to both the naming exception and
         --             naming scheme cases???
         --      3- If either one or the other method resulted in a match,
         --         - update the source/unit interface containers as done in
         --           the previous implementation (except that the unit and
         --           source interface cases are now handled separately).
         --         - Create the GPR2.Source object. We now have different
         --           constructors for Ada and for other languages. This change
         --           is just to make things more explicit. In addition to the
         --           Units argument, the Ada source constructor
         --           takes a new argument Is_RTS_Source, used to handle this
         --           special case when parsing the source.
         --         - Create the GPR2.Project.Source. Nothing special here.
         --           A new check is added to report duplicate project sources.
         --           Add it to the project definition.
         --         - For Ada, create/add the source object to the project
         --           definition: no change from the initial code, but it is
         --           now inside a loop over the compilation units.
         --         - Exit.

         procedure Check_Naming_Exceptions
           (Basename : Value_Type;
            Language : Name_Type;
            Match    : out Boolean;
            Kind     : out Unit.Kind_Type);
         --  Try to match a file using its Basename and the project's
         --  naming exceptions for Language.
         --  If Language is Ada, use the attributes "for Body|Spec ... ".
         --  For other languages, use the attributes:
         --    for (Implementation|Specification)_Exceptions ...".
         --  If success, set Match to True and Kind to the appropriate value.

         procedure Check_Naming_Scheme
           (Basename : Value_Type;
            Language : Name_Type;
            Match    : out Boolean;
            Kind     : out Unit.Kind_Type);
         --  Try to match a file using its extension and the project's
         --  naming scheme for Language.
         --  If Language is Ada, use the attributes "for (Body|Spec|
         --    Separate)_Suffix ... ".
         --  For other languages, use only Body|Spec.
         --  If success, set Match to True and Kind to the appropriate value.

         function Compute_Unit_From_Filename
           (File    : Path_Name.Object;
            Kind    : Unit.Kind_Type;
            Success : out Boolean) return Name_Type;
         --  For an Ada source and given its kind, try to compute a valid unit
         --  name. Success takes True if such a valid name is found.

         -----------------------------
         -- Check_Naming_Exceptions --
         -----------------------------

         procedure Check_Naming_Exceptions
           (Basename : Value_Type;
            Language : Name_Type;
            Match    : out Boolean;
            Kind     : out Unit.Kind_Type)
         is
            Attr : Attribute.Object;
         begin
            Match := False;
            Kind  := Unit.S_Spec;  --  Dummy value

            if Language = "Ada" then
               Match := Ada_Naming_Exceptions.Contains (Basename);

            else
               if Naming.Check_Attribute
                    (PRA.Specification_Exceptions,
                     String (Language),
                     Result => Attr)
                 and then Attr.Has_Value (Basename)
               then
                  Match := True;
                  Kind  := Unit.S_Spec;

               elsif Naming.Check_Attribute
                    (PRA.Implementation_Exceptions,
                     String (Language),
                     Result => Attr)
                 and then Attr.Has_Value (Basename)
               then
                  Match := True;
                  Kind  := Unit.S_Body;
               end if;

               if Match then
                  Other_Except_Usage.Delete (Basename);
               end if;
            end if;
         end Check_Naming_Exceptions;

         -------------------------
         -- Check_Naming_Scheme --
         -------------------------

         procedure Check_Naming_Scheme
           (Basename : Value_Type;
            Language : Name_Type;
            Match    : out Boolean;
            Kind     : out Unit.Kind_Type)
         is
            function Ends_With (Str, Ending : Value_Type) return Boolean
              with Inline;
            --  Returns True if Str ends with the string Ending

            ---------------
            -- Ends_With --
            ---------------

            function Ends_With (Str, Ending : Value_Type) return Boolean is
            begin
               if Str'Length >= Ending'Length then
                  return (Strings.Fixed.Tail
                          (String (Str), Ending'Length)) = Ending;
               else
                  return False;
               end if;
            end Ends_With;

         begin
            Match := False;
            Kind  := Unit.S_Spec;

            if Naming.Has_Spec_Suffix (Language) then
               Check_Spec : declare
                  Spec_Suffix : constant Project.Attribute.Object :=
                                  Naming.Spec_Suffix (Language);
               begin
                  if Ends_With (Basename, Spec_Suffix.Value.Text) then
                     Match := True;
                     Kind  := Unit.S_Spec;
                     return;
                  end if;
               end Check_Spec;
            end if;

            if Naming.Has_Body_Suffix (Language) then
               Check_Body : declare
                  Body_Suffix : constant Project.Attribute.Object :=
                                  Naming.Body_Suffix (Language);
               begin
                  if Ends_With (Basename, Body_Suffix.Value.Text) then
                     Match := True;
                     Kind  := Unit.S_Body;
                     --  May be actually a Separate, we cannot know until
                     --  we parse the file.

                     return;
                  end if;
               end Check_Body;
            end if;

            --  Separate_Suffix is only valid for Ada

            if Language = "Ada"
              and then Naming.Has_Separate_Suffix (Language)
            then
               Check_Separate : declare
                  Sep_Suffix : constant Project.Attribute.Object :=
                                 Naming.Separate_Suffix (Language);
               begin
                  if Ends_With (Basename, Sep_Suffix.Value.Text) then
                     Match := True;
                     Kind  := Unit.S_Separate;
                  end if;
               end Check_Separate;
            end if;
         end Check_Naming_Scheme;

         --------------------------------
         -- Compute_Unit_From_Filename --
         --------------------------------

         function Compute_Unit_From_Filename
           (File    : Path_Name.Object;
            Kind    : Unit.Kind_Type;
            Success : out Boolean) return Name_Type
         is
            use Ada.Strings;
            use Ada.Strings.Maps;

            Result : Unbounded_String :=
                       To_Unbounded_String (String (File.Simple_Name));
         begin
            --  First remove the suffix for the given language

            declare
               Suffix : constant Value_Type :=
                          (case Kind is
                              when S_Spec | S_Spec_Only =>
                                Naming.Spec_Suffix ("ada").Value.Text,
                              when S_Body | S_Body_Only =>
                                Naming.Body_Suffix ("ada").Value.Text,
                              when S_Separate           =>
                                Naming.Separate_Suffix ("ada").Value.Text);
            begin
               if Length (Result) > Suffix'Length then
                  Delete
                    (Result,
                     From    => Length (Result) - Suffix'Length + 1,
                     Through => Length (Result));
               end if;
            end;

            --  If Dot_Replacement is not a single dot, then there should not
            --  be any dot in the name.

            if Dot_Repl /= "." then
               if Index (Result, ".") /= 0 then
                  Tree.Append_Message
                    (Message.Create
                       (Message.Error, "invalid name, contains dot",
                        Source_Reference.Create (File.Value, 1, 1)));
                  goto Invalid;

               else
                  declare
                     I : Natural := 1;
                  begin
                     loop
                        I := Index (Result, Dot_Repl, From => I);
                        exit when I = 0;

                        Replace_Slice
                          (Result, I, I + Dot_Repl'Length - 1, ".");
                     end loop;
                  end;
               end if;
            end if;

            --  Casing for the unit is all lowercase

            Translate (Result, Maps.Constants.Lower_Case_Map);

            --  In the standard GNAT naming scheme, check for special cases:
            --  children or separates of A, G, I or S, and run time sources.

            if Is_Standard_GNAT_Naming and then Length (Result) >= 3 then
               declare
                  S1 : constant Character := Element (Result, 1);
                  S2 : constant Character := Element (Result, 2);
                  S3 : constant Character := Element (Result, 3);

               begin
                  if S1 in 'a' | 'g' | 'i' | 's' then
                     --  Children or separates of packages A, G, I or S. These
                     --  names are x__ ... or x~... (where x is a, g, i, or s).
                     --  Both versions (x__... and x~...) are allowed in all
                     --  platforms, because it is not possible to know the
                     --  platform before processing the project files.

                     if S2 = '_' and then S3 = '_' then
                        --  Replace first _ by a dot
                        Replace_Element (Result, 2, '.');

                        --  and remove the second _
                        Delete (Result, 3, 3);

                     elsif S2 = '~' then
                        Replace_Element (Result, 2, '.');

                     elsif S2 = '.' then

                        --  If it is potentially a run time source

                        null;
                     end if;
                  end if;
               end;
            end if;

            --  Some additional checks on the unit name

            --  Double underscore not allowed

            if Strings.Fixed.Index (To_String (Result), "__") /= 0 then
               goto Invalid;
            end if;

            --  Must start with a letter

            if not Is_In
              (Element (Result, 1), Constants.Letter_Set or To_Set ("_"))
            then
               Tree.Append_Message
                 (Message.Create
                    (Message.Error,
                     "unit '" & To_String (Result)  & "' not valid,"
                     & " should start with a letter or an underscore",
                     Source_Dir_Ref));
               goto Invalid;
            end if;

            --  Cannot have 2 consecutive underscores, cannot have a dot after
            --  an underscore and should contains only alphanumeric characters.

            for K in 2 .. Length (Result) loop
               declare
                  Prev    : constant Character := Element (Result, K - 1);
                  Current : constant Character := Element (Result, K);
               begin
                  if Current = '_' then
                     if Prev = '.' then
                        Tree.Append_Message
                          (Message.Create
                             (Message.Error,
                              "unit '" & To_String (Result)
                              & "' not valid, cannot contain"
                              & " dot after underscore",
                              Source_Dir_Ref));
                        goto Invalid;

                     elsif Prev = '_' then
                        Tree.Append_Message
                          (Message.Create
                             (Message.Error,
                              "unit '" & To_String (Result)
                              & "' not valid, two consecutive"
                              & " underlines not permitted",
                              Source_Dir_Ref));
                        goto Invalid;
                     end if;

                  elsif not Characters.Handling.Is_Alphanumeric (Current)
                    and then Current /= '.'
                  then
                     Tree.Append_Message
                       (Message.Create
                          (Message.Error,
                           "unit '" & To_String (Result)
                           & "' not valid, should have only alpha numeric"
                           & " characters",
                           Source_Dir_Ref));
                     goto Invalid;
                  end if;
               end;
            end loop;

            Success := True;

            return Name_Type (To_String (Result));

            <<Invalid>>

            Success := False;

            return Name_Type (String'("0"));  --  Some dummy unit name
         end Compute_Unit_From_Filename;

         Languages : constant Project.Attribute.Object := Def.Attrs.Languages;

         File      : constant GPR2.Path_Name.Object :=
                       Path_Name.Create_File
                         (Name_Type (Path), Path_Name.No_Resolution);
         Basename  : constant Value_Type := Value_Type (File.Simple_Name);

         Match                  : Boolean := False;

         Source_Is_In_Interface : Boolean := False;
         Has_Naming_Exception   : Boolean := False;
         Units                  : Unit.List.Object;  --  For Ada
         Kind                   : Unit.Kind_Type;
         U_Main                 : constant Unit.Main_Type := Unit.None;
         U_Flags                : constant Unit.Flags_Set :=
                                    Unit.Default_Flags;
         Source                 : GPR2.Source.Object;

         function Naming_Exception_Equal
           (A : Attribute.Object;
            B : Value_Type;
            I : Natural) return Boolean
         is (A.Value.Text = B and then At_Num_Or (A.Value, 1) = I);

      begin
         --  Stop here if it's one of the excluded sources, or it's not in the
         --  included sources if those are given explicitely.

         if Excluded_Sources.Contains (Basename)
           or else not (Included_Sources.Is_Empty
                        or else Included_Sources.Contains (Basename))
         then
            return;
         end if;

         for L of Languages.Values loop
            declare
               Language        : constant Name_Type := Name_Type (L.Text);
               Language_Is_Ada : constant Boolean := Language = "Ada";

            begin
               --  First, try naming exceptions

               Check_Naming_Exceptions
                 (Basename => Basename,
                  Language => Language,
                  Match    => Match,
                  Kind     => Kind);

               if Match then
                  --  Got some naming exceptions for the source

                  Has_Naming_Exception := True;

                  if Language_Is_Ada then
                     --  For Ada, fill the compilation units

                     for Exc of Ada_Naming_Exceptions (Basename) loop
                        declare
                           Unit_Name : constant Name_Type :=
                                         Name_Type (Exc.Index.Text);
                           Index     : constant Natural :=
                                         At_Num_Or (Exc.Value, 1);
                        begin
                           Kind := (if Exc.Name.Text = PRA.Spec
                                    then Unit.S_Spec
                                    else Unit.S_Body);
                           --  May actually be a Separate, we cannot know until
                           --  we parse the file.

                           Ada_Except_Usage.Delete (Ada_Use_Index (Exc));

                           Units.Append
                             (Unit.Create
                                (Name         => Unit_Name,
                                 Index        => Index,
                                 Main         => U_Main,
                                 Flags        => U_Flags,
                                 Kind         => Kind,
                                 Dependencies =>
                                   Source_Reference.Identifier.Set.Empty_Set,
                                 Sep_From     => No_Name));
                        end;
                     end loop;
                  end if;

               else
                  --  If no naming exception matched, try with naming scheme

                  Check_Naming_Scheme
                    (Basename => Basename,
                     Language => Language,
                     Match    => Match,
                     Kind     => Kind);

                  if Match and then Language_Is_Ada then
                     --  For Ada, create a single compilation unit

                     declare
                        Unit_Name : constant Name_Type :=
                                      Compute_Unit_From_Filename
                                        (File    => File,
                                         Kind    => Kind,
                                         Success => Match);

                        function Has_Conflict_NE
                          (Attr_Name : Name_Type) return Boolean;
                        --  Search the Naming package for attributes with name
                        --  Attr_Name and index Unit_Name, and return True if
                        --  at least one of the matching attributes references
                        --  a different (source,index) than the current one.

                        ---------------------
                        -- Has_Conflict_NE --
                        ---------------------

                        function Has_Conflict_NE
                          (Attr_Name : Name_Type) return Boolean is
                        begin
                           for CA in Naming.Attributes.Iterate
                                       (Attr_Name, Value_Type (Unit_Name),
                                        With_Defaults => True)
                           loop
                              if not Naming_Exception_Equal
                                       (Attribute.Set.Element (CA),
                                        Basename, 1)
                              then
                                 return True;
                              end if;
                           end loop;

                           return False;
                        end Has_Conflict_NE;

                     begin
                        if Match then
                           --  Check if we have conflicting naming exceptions:
                           --  same (unit,kind) but different source.
                           --  In this case we skip this source.

                           if (Kind = Unit.S_Spec
                               and then Has_Conflict_NE (PRA.Spec))
                             or else
                               (Kind = Unit.S_Body
                                and then Has_Conflict_NE (PRA.Body_N))
                           then
                              return;
                           end if;

                           Units.Append
                             (Unit.Create
                                (Name         => Unit_Name,
                                 Index        => 1,
                                 Main         => U_Main,
                                 Flags        => U_Flags,
                                 Kind         => Kind,
                                 Dependencies =>
                                   Source_Reference.Identifier.Set.Empty_Set,
                                 Sep_From     => No_Name));
                        end if;
                     end;
                  end if;
               end if;

               --  Got a match from either naming exception or scheme

               if Match then
                  Mark_Language (Language);

                  Source_Is_In_Interface :=
                    Interface_Sources.Contains (Basename);
                  --  Different Source constructors for Ada and other
                  --  languages. Also some additional checks for Ada.

                  if Language_Is_Ada then
                     for CU of Units loop
                        if Interface_Units.Contains (CU.Name)
                          and then CU.Kind in S_Spec | S_Spec_Only
                        then
                           Interface_Units_Found.Include (CU.Name);
                           Source_Is_In_Interface := True;
                        end if;
                     end loop;

                     Source := GPR2.Source.Create_Ada
                          (Filename          => File,
                           Units => Units,
                           Is_RTS_Source     =>
                             (View.Tree.Has_Runtime_Project
                              and then View = View.Tree.Runtime_Project));

                  else
                     Source := GPR2.Source.Create (File, Language, Kind);
                  end if;

                  --  Final processing

                  if Source_Is_In_Interface then
                     Interface_Sources.Exclude (Basename);
                  end if;

                  declare
                     Is_Interface   : constant Boolean :=
                                        Source_Is_In_Interface
                                            or else
                                        (not Interface_Found
                                         and then View.Kind in K_Library
                                         and then
                                         Source.Kind in
                                           Unit.S_Spec | Unit.S_Spec_Only);
                     Project_Source : constant GPR2.Project.Source.Object :=
                                        Project.Source.Create
                                          (Source               => Source,
                                           View                 => View,
                                           Is_Interface         =>
                                             Is_Interface,
                                           Has_Naming_Exception =>
                                             Has_Naming_Exception,
                                           Is_Compilable        =>
                                             Is_Compilable (Language));

                  --  Check source duplication and insert if possible or
                  --  replace if necessary.

                     CS : constant Project.Source.Set.Cursor :=
                            Src_Dir_Set.Find (Project_Source);
                  begin
                     if Project.Source.Set.Has_Element (CS) then
                        if Src_Dir_Set (CS).Has_Naming_Exception
                          < Project_Source.Has_Naming_Exception
                        then
                           --  We are here only when
                           --  Src_Dir_Set (CS).Has_Naming_Exception is False
                           --  and Project_Source.Has_Naming_Exception is True.
                           --  Module with naming exception has priority after
                           --  default naming. Replace the old source with the
                           --  new one.

                           Src_Dir_Set.Replace (Project_Source);

                        elsif Src_Dir_Set (CS).Has_Naming_Exception
                          = Project_Source.Has_Naming_Exception
                        then
                           --  We are here when duplicated sources have naming
                           --  exception or does not have it both.

                           Tree.Append_Message
                             (Message.Create
                                (Message.Error,
                                 '"' & String (File.Simple_Name) & '"'
                                 & " is found in several source directories",
                                 Source_Dir_Ref));
                           return;

                        else
                           --  Remains condition when old source has naming
                           --  exception but new one does not have it. We don't
                           --  need to do anything because of more priority
                           --  source already in its place.

                           return;
                        end if;

                     else
                        Src_Dir_Set.Insert (Project_Source);
                     end if;

                     --  For Ada, register the Unit object into the view

                     if Language_Is_Ada then
                        Register_Units (Project_Source, Units);
                     end if;
                  end;

                  --  Exit the languages loop

                  exit;
               end if;
            end;
         end loop;
      end Handle_File;

      ------------
      -- Insert --
      ------------

      procedure Insert
        (Sources : Project.Source.Set.Object;
         Mode    : Insert_Mode;
         Sloc    : Source_Reference.Object'Class)
      is
         procedure Add_Source (Src : Project.Source.Object);

         procedure Source_Message (Src : Project.Source.Object);

         ----------------
         -- Add_Source --
         ----------------

         procedure Add_Source (Src : Project.Source.Object) is
            --
            --  TODO: avoid the code duplication from Handle_File
            --

            File                   : constant Path_Name.Object :=
                                       Src.Source.Path_Name;
            Basename               : constant Value_Type :=
                                       Value_Type (File.Base_Name);
            Language               : constant Name_Type := Src.Source.Language;
            Language_Is_Ada        : constant Boolean := Language = "Ada";
            Units                  : Unit.List.Object;
            Source_Is_In_Interface : Boolean :=
                                       Interface_Sources.Contains (Basename);

         begin
            Mark_Language (Language);

            --  Different Source constructors for Ada and other
            --  languages. Also some additional checks for Ada.

            if Language_Is_Ada then
               Units := Src.Source.Units;

               for CU of Units loop
                  if Interface_Units.Contains (CU.Name) then
                     Interface_Units_Found.Include (CU.Name);
                     Source_Is_In_Interface := True;
                  end if;
               end loop;
            end if;

            --  Final processing

            if Source_Is_In_Interface then
               Interface_Sources.Exclude (Basename);
            end if;

            Def.Sources.Insert (Src);

            --  For Ada, register the Unit object into the view

            if Language_Is_Ada then
               Register_Units (Src, Units);
            end if;
         end Add_Source;

         --------------------
         -- Source_Message --
         --------------------

         procedure Source_Message (Src : Project.Source.Object) is
         begin
            Tree.Append_Message
              (Message.Create
                 (Message.Error,
                  "project """ & String (Src.View.Name)
                  & """, """ & Src.Source.Path_Name.Value & '"',
                  Sloc, Indent => 1));
         end Source_Message;

         C : Project.Source.Set.Cursor;

      begin
         for Source of Sources loop
            C := Def.Sources.Find (Source);

            if Project.Source.Set.Has_Element (C) then
               case Mode is
                  when Error =>
                     Tree.Append_Message
                       (Message.Create
                          (Message.Error,
                           "source """ & String
                             (Source.Source.Path_Name.Simple_Name)
                           & """ cannot belong to several projects",
                           Sloc));

                     Source_Message (Project.Source.Set.Element (C));
                     Source_Message (Source);

                  when Skip =>
                     null;
               end case;

            else
               --  Do not just insert into Def.Sources: we need to do the same
               --  operations as in Handle_File, except that the Source object
               --  is already constructed here.

               Add_Source (Source);
            end if;
         end loop;
      end Insert;

      -------------------
      -- Is_Compilable --
      -------------------

      function Is_Compilable (Language : Name_Type) return Boolean is

         function Check_View (View : Project.View.Object) return Boolean
           with Pre => View.Is_Defined;
         --  Check if View has a driver for the source language

         ----------------
         -- Check_View --
         ----------------

         function Check_View (View : Project.View.Object) return Boolean is
            Pck : Project.Pack.Object;
            Att : Project.Attribute.Object;
         begin
            if View.Has_Packages (PRP.Compiler) then
               Pck := View.Pack (PRP.Compiler);

               if Pck.Check_Attribute
                 (PRA.Driver, Value_Type (Language), Result => Att)
               then
                  return Att.Value.Text /= "";
               end if;
            end if;

            return False;
         end Check_View;

         Res : Boolean;

      begin
         if Language_Compilable.Contains (Language) then
            Res := Language_Compilable (Language);

         else
            Res := Check_View (View);

            if not Res and then View.Tree.Has_Configuration then
               Res := Check_View (View.Tree.Configuration.Corresponding_View);
            end if;

            Language_Compilable.Insert (Language, Res);
         end if;

         return Res;
      end Is_Compilable;

      -------------------
      -- Mark_Language --
      -------------------

      procedure Mark_Language (Lang : Name_Type) is
         CL : Name_Type_Set.Cursor;
         OK : Boolean;
      begin
         Has_Src_In_Lang.Insert (Lang, CL, OK);
      end Mark_Language;

      ---------------
      -- Read_File --
      ---------------

      procedure Read_File
        (Filename : GPR2.Path_Name.Full_Name;
         Set      : in out Source_Set.Set)
      is
         F      : Text_IO.File_Type;
         Buffer : String (1 .. 1_024);
         Last   : Natural;
      begin
         Text_IO.Open (F, Text_IO.In_File, Filename);

         while not Text_IO.End_Of_File (F) loop
            Text_IO.Get_Line (F, Buffer, Last);
            Set.Include (Buffer (Buffer'First .. Last));
         end loop;

         Text_IO.Close (F);
      end Read_File;

      --------------------
      -- Register_Units --
      --------------------

      procedure Register_Units
        (Source : Project.Source.Object;
         Units  : Unit.List.Object)
      is

         File : constant Path_Name.Object := Source.Source.Path_Name;

         procedure Register_Src
           (U_Def : in out Unit_Info.Object;
            Kind  : Unit.Kind_Type);
         --  Register Project_Source into U_Def, according to its kind

         ------------------
         -- Register_Src --
         ------------------

         procedure Register_Src
           (U_Def : in out Unit_Info.Object;
            Kind  : Unit.Kind_Type)
         is
            use all type Unit.Kind_Type;
         begin
            case Kind is
               when Unit.Spec_Kind =>
                  U_Def.Update_Spec (Source.Path_Name);
               when Unit.Body_Kind =>
                  U_Def.Update_Body (Source.Path_Name);
               when S_Separate =>
                  U_Def.Update_Separates (Source.Path_Name);
            end case;
         end Register_Src;

      begin
         for CU of Units loop
            declare
               Unit_Name : constant Name_Type := CU.Name;
               U_Def     : Unit_Info.Object;
            begin
               Def.Tree.Record_View
                 (View   => View,
                  Source => File.Value,
                  Unit   => Unit_Name);

               if Def.Units.Contains (Unit_Name) then
                  U_Def := Def.Units.Element (Unit_Name);

                  Register_Src (U_Def, CU.Kind);

                  Def.Units.Replace (Unit_Name, U_Def);

               else
                  U_Def := Unit_Info.Create
                    (Unit_Name,
                     Spec      => Path_Name.Undefined,
                     Main_Body => Path_Name.Undefined,
                     Separates => Path_Name.Set.Set.Empty_List);

                  Register_Src (U_Def, CU.Kind);

                  Def.Units.Insert (Unit_Name, U_Def);
               end if;
            end;
         end loop;
      end Register_Units;

      ---------------
      -- Signature --
      ---------------

      function Signature return MD5.Binary_Message_Digest is
         C : MD5.Context;

         procedure Handle (Data : Definition.Data);
         --  Handle the given project's definition

         ------------
         -- Handle --
         ------------

         procedure Handle (Data : Definition.Data) is

            procedure Add (A : Project.Attribute.Object);
            --  Add attribute name and values into the MD5 context

            procedure Add (Attribute_Name : Name_Type);
            --  Add attribute by into the MD5 context

            ---------
            -- Add --
            ---------

            procedure Add (A : Project.Attribute.Object) is
            begin
               MD5.Update (C, String (A.Name.Text) & "/");
               for Value of A.Values loop
                  MD5.Update (C, Value.Text);
               end loop;
            end Add;

            procedure Add (Attribute_Name : Name_Type) is
               Attr : constant Project.Attribute.Object :=
                        Data.Attrs.Element (Attribute_Name);
            begin
               if Attr.Is_Defined then
                  Add (Attr);
               end if;
            end Add;

         begin
            --  The signature to detect the source change is based on the
            --  attributes which are used to compute the actual source set.

            Add (PRA.Languages);
            Add (PRA.Source_Dirs);
            Add (PRA.Source_Files);
            Add (PRA.Excluded_Source_Files);
            Add (PRA.Excluded_Source_List_File);
            Add (PRA.Source_List_File);

            --  Handle also the naming definitions

            if Data.Packs.Contains (PRP.Naming) then
               Handle_Naming : declare
                  Attr   : Attribute.Object;
                  Naming : constant Project.Pack.Object :=
                             Data.Packs (PRP.Naming);
               begin
                  if Naming.Check_Attribute
                       (PRA.Dot_Replacement, Result => Attr)
                  then
                     Add (Attr);
                  end if;

                  for A of Naming.Attributes (PRA.Spec_Suffix) loop
                     Add (A);
                  end loop;

                  for A of Naming.Attributes (PRA.Body_Suffix) loop
                     Add (A);
                  end loop;

                  for A of Naming.Attributes (PRA.Separate_Suffix) loop
                     Add (A);
                  end loop;

                  for CA in Naming.Attributes.Iterate
                              (PRA.Spec, With_Defaults => True)
                  loop
                     Add (Attribute.Set.Element (CA));
                  end loop;

                  for CA in Naming.Attributes.Iterate
                              (PRA.Body_N, With_Defaults => True)
                  loop
                     Add (Attribute.Set.Element (CA));
                  end loop;
               end Handle_Naming;
            end if;
         end Handle;

      begin
         Handle (Def);

         --  If an aggregate library project take into account the
         --  aggregated projects.

         if Def.Kind = K_Aggregate_Library then
            for A of Def.Aggregated loop
               Handle (Definition.Get_RO (A).all);
            end loop;
         end if;

         return MD5.Digest (C);
      end Signature;

      Current_Signature : MD5.Binary_Message_Digest;

      Root              : constant GPR2.Path_Name.Full_Name := Def.Path.Value;

   begin
      --  Check if up-to-date using signature for source_dirs, source_files...
      --  An abstract or aggregate project has no sources.

      if Def.Kind in K_Abstract | K_Aggregate then
         return;
      end if;

      Current_Signature := Signature;

      if Def.Sources_Signature = Current_Signature then
         return;
      end if;

      --  Setup the naming exceptions look-up table if needed

      Fill_Ada_Naming_Exceptions (PRA.Spec);
      Fill_Ada_Naming_Exceptions (PRA.Body_N);

      Fill_Other_Naming_Exceptions
        (Naming.Attributes (PRA.Specification_Exceptions));
      Fill_Other_Naming_Exceptions
        (Naming.Attributes (PRA.Implementation_Exceptions));

      --  Record units being set as interfaces, first for Library_Interface
      --  which contains unit names.

      if Def.Attrs.Has_Library_Interface then
         Interface_Found := True;

         for Unit of Def.Attrs.Library_Interface.Values loop
            if Interface_Units.Contains (Name_Type (Unit.Text)) then
               Tree.Append_Message
                 (Message.Create
                    (Message.Warning,
                     "duplicate unit '" & Unit.Text
                     & "' in library_interface attribute",
                     Def.Attrs.Library_Interface));
            else
               Interface_Units.Insert
                 (Name_Type (Unit.Text), Source_Reference.Object (Unit));
            end if;
         end loop;
      end if;

      --  And then for Interfaces which contains filenames

      if Def.Attrs.Has_Interfaces then
         Interface_Found := True;

         for Source of Def.Attrs.Interfaces.Values loop
            if Interface_Sources.Contains (Source.Text) then
               Tree.Append_Message
                 (Message.Create
                    (Message.Warning,
                     "duplicate source '" & Source.Text
                     & "' in interfaces attribute",
                     Def.Attrs.Interfaces));
            else
               Interface_Sources.Insert
                 (Source.Text, Source_Reference.Object (Source));
            end if;
         end loop;
      end if;

      --  Read sources and set up the corresponding definition

      --  First reset the current set

      Def.Sources.Clear;

      --  Clear the units record, note that we also want to record the
      --  unit_name -> view lookup table in the tree.

      for U of Def.Units loop
         Def.Tree.Clear_View (Unit => U);
      end loop;

      Def.Units.Clear;

      --  If we have attribute Excluded_Source_List_File

      if Def.Attrs.Has_Excluded_Source_List_File then
         declare
            File : constant GPR2.Path_Name.Full_Name :=
                     Directories.Compose
                       (Root,
                        Def.Attrs.Element (PRA.Excluded_Source_List_File)
                        .Value.Text);
         begin
            Read_File (File, Excluded_Sources);
         end;
      end if;

      --  If we have attribute Excluded_Source_Files

      if Def.Attrs.Has_Excluded_Source_Files then
         for File of Def.Attrs.Excluded_Source_Files.Values loop
            Excluded_Sources.Include (File.Text);
         end loop;
      end if;

      --  If we have attribute Source_List_File

      if Def.Attrs.Has_Source_List_File then
         declare
            File : constant GPR2.Path_Name.Full_Name :=
                     Directories.Compose
                       (Root,
                        Def.Attrs.Element (PRA.Source_List_File).Value.Text);
         begin
            Read_File (File, Included_Sources);
         end;
      end if;

      --  If we have attribute Source_Files

      if Def.Attrs.Has_Source_Files then
         for File of Def.Attrs.Source_Files.Values loop
            Included_Sources.Include (File.Text);
         end loop;
      end if;

      if Def.Kind = K_Aggregate_Library then
         --  Sources for an aggregate library is the cumulative set of
         --  sources of the aggregated projects.

         for Agg of Def.Aggregated loop
            declare
               DA : constant Const_Ref := Get_RO (Agg);
            begin
               declare
                  In_Interface : Boolean := False;
                  A_Set        : Project.Source.Set.Object;
               begin
                  for P of Agg.Sources loop
                     In_Interface :=
                       Interface_Sources.Contains
                         (String (P.Source.Path_Name.Base_Name));

                     if P.Source.Has_Units then
                        for CU of P.Source.Units loop
                           if Interface_Units.Contains (CU.Name) then
                              Interface_Units_Found.Include (CU.Name);
                              In_Interface := True;
                           end if;
                        end loop;
                     end if;

                     declare
                        use all type Unit.Kind_Type;

                        Is_Interface : constant Boolean :=
                                         In_Interface
                                             or else
                                         (not Interface_Found
                                          and then P.Source.Kind = S_Spec);
                     begin
                        --  An aggregate library project does not allow naming
                        --  exception. So the source naming exception status is
                        --  the one from the aggregated project.

                        A_Set.Insert
                          (Project.Source.Create
                             (Source               => P.Source,
                              View                 => P.View,
                              Is_Interface         => Is_Interface,
                              Has_Naming_Exception => P.Has_Naming_Exception,
                              Is_Compilable        => P.Is_Compilable,
                              Aggregated           => True));
                     end;
                  end loop;

                  Insert
                    (A_Set,
                     Error,
                     (if DA.Attrs.Has_Source_Dirs
                      then DA.Attrs.Source_Dirs
                      else Source_Reference.Create
                        (DA.Trees.Project.Path_Name.Value, 0, 0)));
               end;
            end;
         end loop;

      elsif View.Kind not in K_Configuration | K_Abstract then
         --  Handle Source_Dirs

         for Dir of View.Source_Directories.Values loop
            --  Keep reference for error messages

            Source_Dir_Ref := Source_Reference.Object (Dir);

            if OS_Lib.Is_Absolute_Path (Dir.Text) then
               Handle_Directory (Dir.Text);
            else
               Handle_Directory (Root & OS_Lib.Directory_Separator & Dir.Text);
            end if;

            Def.Sources.Union (Src_Dir_Set);
            Src_Dir_Set.Clear;
         end loop;

         for C in Ada_Except_Usage.Iterate loop
            declare
               Key : constant Value_Type := Naming_Exceptions_Usage.Key (C);
            begin
               pragma Assert (Key (Key'Last) in 'B' | 'S', Key);

               Tree.Append_Message
                 (Message.Create
                    (Message.Error,
                     "source file """
                     & Naming_Exceptions_Usage.Element (C).Text
                     & """ for unit """ & Key (Key'First .. Key'Last - 1)
                     --  Last character in Key is 'B' - Body or 'S' - Spec
                     & """ not found",
                     Naming_Exceptions_Usage.Element (C)));
            end;
         end loop;

         for V of Other_Except_Usage loop
            Tree.Append_Message
              (Message.Create
                 (Message.Warning,
                  "source file """ & V.Text & """ not found",
                  V));
         end loop;
      end if;

      --  Finally get the sources from the extended project if defined. We
      --  only add the sources not already defined in the current set.

      if Def.Extended.Is_Defined then
         Insert (Def.Extended.Sources, Skip, Source_Reference.Undefined);
      end if;

      if Def.Attrs.Languages.Is_Defined and then Def.Kind /= K_Abstract then
         for L of Def.Languages loop
            if not Has_Src_In_Lang.Contains (Name_Type (L.Text)) then
               Tree.Append_Message
                 (Message.Create
                    (Message.Warning,
                     "there are no sources of language """ & L.Text
                     & """ in this project",
                     L));
            end if;
         end loop;
      end if;

      --  And update the interface units bookkeeping

      for U of Interface_Units_Found loop
         Interface_Units.Exclude (U);
      end loop;

      --  Check that all unit and source interfaces have been found in the
      --  project view.

      for Cur in Interface_Units.Iterate loop
         declare
            Sloc      : constant Source_Reference.Object :=
                          Unit_Name_To_Sloc.Element (Cur);
            Unit_Name : constant Name_Type :=
                          Unit_Name_To_Sloc.Key (Cur);
         begin
            Tree.Append_Message
              (Message.Create
                 (Message.Error,
                  "source for interface unit"
                  & " '"
                  & String (Unit_Name)
                  & "' not found",
                  Sloc));
         end;
      end loop;

      for Cur in Interface_Sources.Iterate loop
         declare
            Sloc        : constant Source_Reference.Object :=
                            Source_Path_To_Sloc.Element (Cur);
            Source_Path : constant Value_Type :=
                            Source_Path_To_Sloc.Key (Cur);
         begin
            Tree.Append_Message
              (Message.Create
                 (Message.Error,
                  "source for "
                  & " '"
                  & String (Source_Path)
                  & "' not found",
                  Sloc));
         end;
      end loop;

      --  Record back new definition for the view with updated sources

      Def.Sources_Signature := Current_Signature;

      Source_Info.Parser.Registry.Clear_Cache;

      if Message_Count < Tree.Log_Messages.Count
        and then Tree.Log_Messages.Has_Error
      then
         --  Some error messages have been logged, raise an exception
         raise Project_Error with "cannot retrieve the sources";
      end if;
   end Update_Sources;

begin
   --  Setup the default/built-in naming package

   Builtin_Naming_Package :=
     Project.Pack.Create
       (Source_Reference.Identifier.Object
          (Source_Reference.Identifier.Create
             (Source_Reference.Builtin, PRP.Naming)),
        Project.Attribute.Set.Empty_Set,
        Project.Variable.Set.Set.Empty_Map);
end GPR2.Project.Definition;
