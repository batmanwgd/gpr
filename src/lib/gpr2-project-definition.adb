------------------------------------------------------------------------------
--                                                                          --
--                           GPR2 PROJECT MANAGER                           --
--                                                                          --
--                       Copyright (C) 2019, AdaCore                        --
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
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Containers.Doubly_Linked_Lists;
with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Strings.Maps.Constants;
with Ada.Text_IO;
with Ada.Strings.Unbounded;

with GNAT.MD5;
with GNAT.OS_Lib;

with GPR2.Compilation_Unit;
with GPR2.Compilation_Unit.List;
with GPR2.Message;
with GPR2.Path_Name;
with GPR2.Project.Attribute;
with GPR2.Project.Registry.Attribute;
with GPR2.Project.Registry.Pack;
with GPR2.Project.Tree;
with GPR2.Source;
with GPR2.Source_Reference.Identifier;
with GPR2.Source_Reference.Identifier.Set;
with GPR2.Source_Reference.Value;

package body GPR2.Project.Definition is

   use Ada;
   use GNAT;

   Builtin_Naming_Package : Project.Pack.Object;
   --  The default naming package to use if no Naming package specified in the
   --  project and no configuration file loaded. We at least want to handle in
   --  this case the standard Ada and C namings.

   Builtin_Languages : Project.Attribute.Object;
   --  The default languages to use if no languages attribute specified in the
   --  project. The default value is just "ada".

   function Source_Directories (Def : Data) return Project.Attribute.Object is
     (if Def.Attrs.Has_Source_Dirs
      then Def.Attrs.Source_Dirs
      else Project.Attribute.Default_Source_Dirs);

   function Languages (Def : Data) return Containers.Source_Value_List is
     (if Def.Attrs.Has_Languages
      then Def.Attrs.Languages.Values
      else Builtin_Languages.Values);

   --------------------
   -- Naming_Package --
   --------------------

   function Naming_Package (Def : Data) return Project.Pack.Object is
   begin
      if Def.Has_Packages (Registry.Pack.Naming) then
         declare
            Naming : constant Project.Pack.Object :=
                       Def.Packs (Registry.Pack.Naming);
            Result : Project.Attribute.Set.Object :=
                       Builtin_Naming_Package.Attributes;
         begin
            --  Result is built-in package attributes, now we want to replace
            --  the attribute as defined in the project.

            for A of Naming.Attributes loop
               Result.Include (A);
            end loop;

            return Project.Pack.Create
              (Name       =>
                 Source_Reference.Identifier.Object
                   (Source_Reference.Identifier.Create
                      (Source_Reference.Object (Naming),
                       Registry.Pack.Naming)),
               Attributes => Result,
               Variables  => Project.Variable.Set.Set.Empty_Map);
         end;

      elsif Def.Tree.Has_Configuration then
         return Def.Tree.Configuration.Corresponding_View.Naming_Package;

      else
         return Builtin_Naming_Package;
      end if;
   end Naming_Package;

   --------------------
   -- Update_Sources --
   --------------------

   procedure Update_Sources (Def : in out Data; View : Project.View.Object) is

      use type Ada.Containers.Count_Type;
      use type MD5.Binary_Message_Digest;
      use type Project.Attribute.Object;

      use GPR2.Containers;
      use GPR2.Path_Name;

      use type Source_Reference.Object;

      Source_Dir_Ref : Source_Reference.Object;

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

      type Insert_Mode is (Replace, Skip, Error);
      --  Controls behavior when a duplicated unit/filename is found
      --
      --  Replace : the new source replace the previous one
      --  Skip    : the new source is ignored
      --  Error   : an error is raised

      package Source_Set is
        new Ada.Containers.Indefinite_Ordered_Sets (Value_Type);

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
      --  Insert Sources into Data.Sources

      procedure Fill_Ada_Naming_Exceptions (Set : Project.Attribute.Set.Object)
        with Pre =>
          (for all A of Set =>
             A.Name = Registry.Attribute.Spec
             or else A.Name = Registry.Attribute.Specification
             or else A.Name = Registry.Attribute.Body_N
             or else A.Name = Registry.Attribute.Implementation);
      --  Fill the Ada_Naming_Exceptions object with the given attribute set

      Naming : constant Project.Pack.Object := Naming_Package (Def);
      --  Package Naming for the view

      Dot_Repl : constant String :=
                   Naming.Attribute
                     (Registry.Attribute.Dot_Replacement).Value.Text;
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

      Included_Sources  : Source_Set.Set;
      Excluded_Sources  : Source_Set.Set;

      Interface_Units       : Unit_Name_To_Sloc.Map;
      Interface_Units_Found : Name_Set;
      Interface_Sources     : Source_Path_To_Sloc.Map;

      Tree              : constant not null access Project.Tree.Object :=
                            Def.Tree;

      Message_Count     : constant Containers.Count_Type :=
                            Tree.Log_Messages.Count;

      Ada_Naming_Exceptions : Source_Path_To_Attribute_List.Map;

      --------------------------------
      -- Fill_Ada_Naming_Exceptions --
      --------------------------------

      procedure Fill_Ada_Naming_Exceptions
        (Set : Project.Attribute.Set.Object) is
      begin
         for A of Set loop
            declare
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
                  Ada_Naming_Exceptions.Reference (Source).Append (A);
               end if;
            end;
         end loop;
      end Fill_Ada_Naming_Exceptions;

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
      end Handle_Directory;

      -----------------
      -- Handle_File --
      -----------------

      procedure Handle_File (Path : GPR2.Path_Name.Full_Name) is
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
         --           Compilation_Units argument, the Ada source constructor
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
            Kind     : out Kind_Type);
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
            Kind     : out Kind_Type);
         --  Try to match a file using its extension and the project's
         --  naming scheme for Language.
         --  If Language is Ada, use the attributes "for (Body|Spec|
         --    Separate)_Suffix ... ".
         --  For other languages, use only Body|Spec.
         --  If success, set Match to True and Kind to the appropriate value.

         function Compute_Unit_From_Filename
           (File    : Path_Name.Object;
            Kind    : Kind_Type;
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
            Kind     : out Kind_Type) is
         begin
            Match := False;
            Kind  := S_Spec;  --  Dummy value

            if Language = "Ada" then
               Match := Ada_Naming_Exceptions.Contains (Basename);

            else
               if Naming.Has_Attributes
                 (Registry.Attribute.Specification_Exceptions,
                  String (Language))
               then
                  if Naming.Attribute
                    (Registry.Attribute.Specification_Exceptions,
                     String (Language)).Has_Value (String (Basename))
                  then
                     Match := True;
                     Kind  := S_Body;
                  end if;
               end if;

               if Naming.Has_Attributes
                 (Registry.Attribute.Implementation_Exceptions,
                  String (Language))
               then
                  if Naming.Attribute
                    (Registry.Attribute.Implementation_Exceptions,
                     String (Language)).Has_Value (String (Basename))
                  then
                     if Match then
                        Tree.Append_Message
                          (Message.Create
                             (Message.Error,
                              "the same file cannot be a source "
                              & "and a template",
                              Naming.Attribute
                                (Registry.Attribute.Implementation_Exceptions,
                                 String (Language)).Value
                              (String (Basename))));
                     else
                        Match := True;
                        Kind  := S_Spec;
                     end if;
                  end if;
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
            Kind     : out Kind_Type)
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
            Kind  := S_Spec;

            Check_Spec : declare
               Spec_Suffix : constant Project.Attribute.Object :=
                               Naming.Spec_Suffix (Language);
            begin
               if Spec_Suffix.Is_Defined
                 and then Ends_With (Basename, Spec_Suffix.Value.Text)
               then
                  Match := True;
                  Kind  := S_Spec;
                  return;
               end if;
            end Check_Spec;

            Check_Body : declare
               Body_Suffix : constant Project.Attribute.Object :=
                               Naming.Body_Suffix (Language);
            begin
               if Body_Suffix.Is_Defined
                 and then Ends_With (Basename, Body_Suffix.Value.Text)
               then
                  Match := True;
                  Kind  := S_Body;
                  --  May be actually a Separate, we cannot know until
                  --  we parse the file.

                  return;
               end if;
            end Check_Body;

            --  Separate_Suffix is only valid for Ada

            if Language = "Ada" then
               Check_Separate : declare
                  Sep_Suffix : constant Project.Attribute.Object :=
                                 Naming.Separate_Suffix (Language);
               begin
                  if Sep_Suffix.Is_Defined
                    and then Ends_With (Basename, Sep_Suffix.Value.Text)
                  then
                     Match := True;
                     Kind  := S_Separate;
                  end if;
               end Check_Separate;
            end if;
         end Check_Naming_Scheme;

         --------------------------------
         -- Compute_Unit_From_Filename --
         --------------------------------

         function Compute_Unit_From_Filename
           (File    : Path_Name.Object;
            Kind    : Kind_Type;
            Success : out Boolean) return Name_Type
         is
            use Ada.Strings;
            use Ada.Strings.Unbounded;

            Result : Unbounded_String :=
                       To_Unbounded_String (String (File.Simple_Name));
         begin
            --  First remove the suffix for the given language

            declare
               Suffix : constant Value_Type :=
                          (case Kind is
                              when S_Spec     =>
                                Naming.Spec_Suffix ("ada").Value.Text,
                              when S_Body     =>
                                Naming.Body_Suffix ("ada").Value.Text,
                              when S_Separate =>
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

            if not Characters.Handling.Is_Letter (Element (Result, 1)) then
               Tree.Append_Message
                 (Message.Create
                    (Message.Error,
                     "unit '" & To_String (Result)
                     & "' not valid, should start with a letter",
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

         Languages : constant Project.Attribute.Object :=
                       (if Def.Has_Attributes (Registry.Attribute.Languages)
                        then Def.Attrs.Element
                          (Registry.Attribute.Languages, No_Value)
                        else Builtin_Languages);

         File : constant GPR2.Path_Name.Object :=
                  Path_Name.Create_File (Name_Type (Path));

         Basename : constant Value_Type := Value_Type (File.Simple_Name);

         Match : Boolean := False;

         Source_Is_In_Interface : Boolean;
         Has_Naming_Exception   : Boolean := False;
         Compilation_Units      : Compilation_Unit.List.Object;  --  For Ada
         Kind                   : Kind_Type;
         Source                 : GPR2.Source.Object;
         Project_Source         : Project.Source.Object;

         function Naming_Exception_Equal
           (A : Attribute.Object;
            B : Value_Type;
            I : Natural) return Boolean
         is (A.Value.Text = B
             and then
               ((A.Has_At_Num and then A.At_Num = I)
                  or else
                (not A.Has_At_Num and then I = 1)));

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
               Language_Is_Ada : constant Boolean := (Language = "Ada");

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
                           use Registry.Attribute;

                           Unit_Name : constant Name_Type :=
                                         Name_Type (Exc.Index.Text);

                           Index : constant Natural :=
                                     (if Exc.Has_At_Num
                                      then Exc.At_Num
                                      else 1);

                        begin
                           Kind := (if Exc.Name = Spec
                                    or else Exc.Name = Specification
                                    then S_Spec
                                    else S_Body);
                           --  May actually be a Separate, we cannot know until
                           --  we parse the file.

                           Compilation_Units.Append
                             (Compilation_Unit.Create
                                (Unit_Name    => Unit_Name,
                                 Index        => Index,
                                 Kind         => Kind,
                                 Withed_Units =>
                                   Source_Reference.Identifier.Set.Empty_Set,
                                 Is_Sep_From  => ""));
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
                           for A of Naming.Attributes
                             (Attr_Name, Value_Type (Unit_Name))
                           loop
                              if
                                not Naming_Exception_Equal (A, Basename, 1)
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

                           if (Kind = S_Spec
                               and then
                                 (Has_Conflict_NE (Registry.Attribute.Spec)
                                  or else
                                  Has_Conflict_NE (Registry.Attribute.
                                                       Specification)))
                             or else
                               (Kind = S_Body
                                and then
                                  (Has_Conflict_NE (Registry.Attribute.Body_N)
                                   or else
                                   Has_Conflict_NE (Registry.Attribute.
                                                        Implementation)))
                           then
                              return;
                           end if;

                           Compilation_Units.Append
                             (Compilation_Unit.Create
                                (Unit_Name    => Unit_Name,
                                 Index        => 1,
                                 Kind         => Kind,
                                 Withed_Units =>
                                   Source_Reference.Identifier.Set.Empty_Set,
                                 Is_Sep_From  => ""));
                        end if;
                     end;
                  end if;
               end if;

               --  Got a match from either naming exception or scheme

               if Match then
                  Source_Is_In_Interface :=
                    Interface_Sources.Contains (Basename);
                  --  Different Source constructors for Ada and other
                  --  languages. Also some additional checks for Ada.

                  if Language_Is_Ada then
                     for CU of Compilation_Units loop
                        if Interface_Units.Contains (CU.Unit_Name) then
                           Interface_Units_Found.Include (CU.Unit_Name);
                           Source_Is_In_Interface := True;
                        end if;
                     end loop;

                     Source := GPR2.Source.Create_Ada
                       (Filename          => File,
                        Compilation_Units => Compilation_Units,
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

                  Project_Source := Project.Source.Create
                    (Source               => Source,
                     View                 => View,
                     Is_Interface         => Source_Is_In_Interface,
                     Has_Naming_Exception => Has_Naming_Exception);

                  if Def.Sources.Contains (Project_Source) then
                     Tree.Append_Message
                       (Message.Create
                          (Message.Error,
                           """" & String (File.Simple_Name)
                           & """ is found in several source directories",
                           Source_Dir_Ref));
                     return;
                  else
                     Def.Sources.Insert (Project_Source);
                  end if;

                  --  For Ada, register the Unit object into the view

                  if Language_Is_Ada then
                     declare
                        U_Def : Unit.Object;

                        procedure Register_Src (Kind : Kind_Type);
                        --  Register Project_Source into U_Def, according to
                        --  its kind.

                        ------------------
                        -- Register_Src --
                        ------------------

                        procedure Register_Src (Kind : Kind_Type) is
                        begin
                           if Kind = S_Spec then
                              U_Def.Update_Spec (Project_Source);
                           elsif Kind = S_Body then
                              U_Def.Update_Body (Project_Source);
                           else
                              U_Def.Update_Separates (Project_Source);
                           end if;
                        end Register_Src;

                     begin
                        for CU of Compilation_Units loop
                           Def.Tree.Record_View
                             (View   => View,
                              Source => File.Value,
                              Unit   => CU.Unit_Name);

                           if Def.Units.Contains (CU.Unit_Name) then
                              U_Def := Def.Units.Element (CU.Unit_Name);

                              Register_Src (CU.Kind);

                              Def.Units.Replace (CU.Unit_Name, U_Def);

                           else
                              Register_Src (CU.Kind);

                              Def.Units.Insert (CU.Unit_Name, U_Def);
                           end if;
                        end loop;
                     end;
                  end if;

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
         C : Project.Source.Set.Cursor;

         procedure Add_Source (Src : Project.Source.Object);

         procedure Source_Message (Src : Project.Source.Object);

         ----------------
         -- Add_Source --
         ----------------

         procedure Add_Source (Src : Project.Source.Object) is
            --
            --  TODO: avoid the code duplication from Handle_File
            --

            Project_Source         : constant Project.Source.Object := Src;
            File                   : constant Path_Name.Object :=
                                       Src.Source.Path_Name;
            Basename               : constant Value_Type :=
                                       Value_Type (File.Base_Name);
            Language               : constant Name_Type := Src.Source.Language;
            Language_Is_Ada        : constant Boolean := Language = "Ada";
            Compilation_Units      : Compilation_Unit.List.Object;
            Source_Is_In_Interface : Boolean :=
                                       Interface_Sources.Contains (Basename);

         begin
            --  Different Source constructors for Ada and other
            --  languages. Also some additional checks for Ada.

            if Language_Is_Ada then
               Compilation_Units := Src.Source.Compilation_Units;

               for CU of Compilation_Units loop
                  if Interface_Units.Contains (CU.Unit_Name) then
                     Interface_Units_Found.Include (CU.Unit_Name);
                     Source_Is_In_Interface := True;
                  end if;
               end loop;
            end if;

            --  Final processing

            if Source_Is_In_Interface then
               Interface_Sources.Exclude (Basename);
            end if;

            Def.Sources.Insert (Project_Source);

            --  For Ada, register the Unit object into the view

            if Language_Is_Ada then
               declare
                  U_Def : Unit.Object;

                  procedure Register_Src (Kind : Kind_Type);
                  --  Register Project_Source into U_Def, according to
                  --  its kind.

                  ------------------
                  -- Register_Src --
                  ------------------

                  procedure Register_Src (Kind : Kind_Type) is
                  begin
                     if Kind = S_Spec then
                        U_Def.Update_Spec (Project_Source);
                     elsif Kind = S_Body then
                        U_Def.Update_Body (Project_Source);
                     else
                        U_Def.Update_Separates (Project_Source);
                     end if;
                  end Register_Src;

               begin
                  for CU of Compilation_Units loop
                     Def.Tree.Record_View
                       (View   => View,
                        Source => File.Value,
                        Unit   => CU.Unit_Name);

                     if Def.Units.Contains (CU.Unit_Name) then
                        U_Def := Def.Units.Element (CU.Unit_Name);

                        Register_Src (CU.Kind);

                        Def.Units.Replace (CU.Unit_Name, U_Def);

                     else
                        Register_Src (CU.Kind);

                        Def.Units.Insert (CU.Unit_Name, U_Def);
                     end if;
                  end loop;
               end;
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

      begin
         for Source of Sources loop
            C := Def.Sources.Find (Source);

            if Project.Source.Set.Has_Element (C) then
               case Mode is
                  when Replace =>
                     Def.Sources.Replace (Source);

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

            ---------
            -- Add --
            ---------

            procedure Add (A : Project.Attribute.Object) is
            begin
               MD5.Update (C, String (A.Name) & "/");
               for Value of A.Values loop
                  MD5.Update (C, Value.Text);
               end loop;
            end Add;

         begin
            --  The signature to detect the source change is based on the
            --  attributes which are used to compute the actual source set.

            if Data.Attrs.Has_Languages then
               Add (Data.Attrs.Languages);
            end if;

            if Data.Attrs.Has_Source_Dirs then
               Add (Data.Attrs.Source_Dirs);
            end if;

            if Data.Attrs.Has_Source_Files then
               Add (Data.Attrs.Source_Files);
            end if;

            if Data.Attrs.Has_Excluded_Source_Files then
               Add (Data.Attrs.Excluded_Source_Files);
            end if;

            if Data.Attrs.Has_Excluded_Source_List_File then
               Add (Data.Attrs.Excluded_Source_List_File);
            end if;

            if Data.Attrs.Has_Source_List_File then
               Add (Data.Attrs.Source_List_File);
            end if;

            --  Handle also the naming definitions

            if Data.Packs.Contains (Project.Registry.Pack.Naming) then
               Handle_Naming : declare
                  use Registry.Attribute;

                  Naming : constant Project.Pack.Object :=
                             Data.Packs (Project.Registry.Pack.Naming);
               begin
                  if Naming.Has_Attributes (Dot_Replacement) then
                     Add (Naming.Attribute (Dot_Replacement));
                  end if;

                  for Attr of Naming.Attributes (Spec_Suffix) loop
                     Add (Attr);
                  end loop;

                  for Attr of Naming.Attributes (Body_Suffix) loop
                     Add (Attr);
                  end loop;

                  for Attr of Naming.Attributes (Separate_Suffix) loop
                     Add (Attr);
                  end loop;

                  for Attr of Naming.Attributes (Spec) loop
                     Add (Attr);
                  end loop;

                  for Attr of Naming.Attributes (Body_N) loop
                     Add (Attr);
                  end loop;

                  for Attr of Naming.Attributes (Specification) loop
                     Add (Attr);
                  end loop;

                  for Attr of Naming.Attributes (Implementation) loop
                     Add (Attr);
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

      Root              : constant GPR2.Path_Name.Full_Name :=
                            Directories.Containing_Directory
                              (Def.Trees.Project.Path_Name.Value);
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

      Fill_Ada_Naming_Exceptions
        (Naming.Attributes (Registry.Attribute.Spec));
      Fill_Ada_Naming_Exceptions
        (Naming.Attributes (Registry.Attribute.Specification));
      Fill_Ada_Naming_Exceptions
        (Naming.Attributes (Registry.Attribute.Body_N));
      Fill_Ada_Naming_Exceptions
        (Naming.Attributes (Registry.Attribute.Implementation));

      --  Record units being set as interfaces, first for Library_Interface
      --  which contains unit names.

      if Def.Attrs.Has_Library_Interface then
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
                        Def.Attrs.Element
                          (Registry.Attribute.Excluded_Source_List_File)
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
                        Def.Attrs.Element
                          (Registry.Attribute.Source_List_File).Value.Text);
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
               Insert
                 (Agg.Sources, Error,
                  (if DA.Attrs.Has_Source_Dirs
                   then DA.Attrs.Source_Dirs
                   else Source_Reference.Create
                     (DA.Trees.Project.Path_Name.Value, 0, 0)));
            end;
         end loop;

      else
         Populate_Sources : begin
            --  Handle Source_Dirs

            for Dir of View.Source_Directories.Values loop
               --  Keep reference for error messages

               Source_Dir_Ref := Source_Reference.Object (Dir);

               if OS_Lib.Is_Absolute_Path (Dir.Text) then
                  Handle_Directory (Dir.Text);
               else
                  Handle_Directory
                    (Root & OS_Lib.Directory_Separator & Dir.Text);
               end if;
            end loop;
         end Populate_Sources;
      end if;

      --  Finally get the sources from the extended project if defined. We
      --  only add the sources not already defined in the current set.

      if Def.Extended.Is_Defined then
         Insert (Def.Extended.Sources, Skip, Source_Reference.Undefined);
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

      if Message_Count < Tree.Log_Messages.Count
        and then Tree.Log_Messages.Has_Error
      then
         --  Some error messages have been logged, raise an exception
         raise Project_Error with "cannot retrieve the sources";
      end if;
   end Update_Sources;

begin
   --  Setup the default/built-in naming package

   declare
      function Create
        (Name : Name_Type; Index, Value : Value_Type)
         return Project.Attribute.Object;
      --  Create attribute Name for the Naming package

      ------------
      -- Create --
      ------------

      function Create
        (Name : Name_Type; Index, Value : Value_Type)
         return Project.Attribute.Object
      is
         A   : Project.Attribute.Object :=
                 Project.Attribute.Create
                   (Source_Reference.Identifier.Object
                      (Source_Reference.Identifier.Create
                         (Source_Reference.Builtin, Name)),
                    (Source_Reference.Value.Object
                      (Source_Reference.Value.Create
                         (Source_Reference.Builtin, Index))),
                    (Source_Reference.Value.Object
                      (Source_Reference.Value.Create
                         (Source_Reference.Builtin, Value))));
         Def : constant Project.Registry.Attribute.Def :=
                 Project.Registry.Attribute.Get
                   (Project.Registry.Attribute.Create
                      (Name, Registry.Pack.Naming));
      begin
         A.Set_Case (Def.Index_Case_Sensitive, Def.Value_Case_Sensitive);
         return A;
      end Create;

      Ada_Spec : constant Project.Attribute.Object :=
                   Create (Registry.Attribute.Spec_Suffix, "ada", ".ads");
      Ada_Body : constant  Project.Attribute.Object :=
                   Create (Registry.Attribute.Body_Suffix, "ada", ".adb");
      C_Spec   : constant Project.Attribute.Object :=
                   Create (Registry.Attribute.Spec_Suffix, "c", ".h");
      C_Body   : constant Project.Attribute.Object :=
                   Create (Registry.Attribute.Body_Suffix, "c", ".c");
      Dot_Repl : constant Project.Attribute.Object :=
                 Project.Attribute.Create
                   (Source_Reference.Identifier.Object
                      (Source_Reference.Identifier.Create
                         (Source_Reference.Builtin,
                          Registry.Attribute.Dot_Replacement)),
                    (Source_Reference.Value.Object
                      (Source_Reference.Value.Create
                         (Source_Reference.Builtin, ""))),
                    (Source_Reference.Value.Object
                      (Source_Reference.Value.Create
                          (Source_Reference.Builtin, "-"))));
      Attrs    : Project.Attribute.Set.Object;
      Langs    : Containers.Source_Value_List;
   begin
      --  Default naming package

      Attrs.Insert (Ada_Spec);
      Attrs.Insert (Ada_Body);
      Attrs.Insert (C_Spec);
      Attrs.Insert (C_Body);
      Attrs.Insert (Dot_Repl);

      Builtin_Naming_Package :=
        Project.Pack.Create
          (Source_Reference.Identifier.Object
             (Source_Reference.Identifier.Create
                (Source_Reference.Builtin, Registry.Pack.Naming)),
           Attrs, Project.Variable.Set.Set.Empty_Map);

      --  Default languages attribute

      Langs.Append
        (Source_Reference.Value.Object
           (Source_Reference.Value.Create (Source_Reference.Builtin, "ada")));
      Builtin_Languages :=
        Project.Attribute.Create
          (Source_Reference.Identifier.Object
             (Source_Reference.Identifier.Create
                (Source_Reference.Builtin, Registry.Attribute.Languages)),
           Langs);
      Builtin_Languages.Set_Case (Value_Is_Case_Sensitive => False);
   end;
end GPR2.Project.Definition;
