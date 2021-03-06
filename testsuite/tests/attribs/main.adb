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

with Ada.Directories;
with Ada.Text_IO;
with GPR2.Project.View;
with GPR2.Project.Tree;
with GPR2.Project.Attribute.Set;
with GPR2.Project.Name_Values;
with GPR2.Project.Registry.Attribute;
with GPR2.Project.Registry.Pack;
with GPR2.Project.Variable.Set;
with GPR2.Context;

procedure Main is

   use Ada;
   use GPR2;
   use GPR2.Project;

   use all type GPR2.Project.Name_Values.Value_Kind;

   procedure Display (Prj : Project.View.Object; Full : Boolean := True);

   -------------
   -- Display --
   -------------

   procedure Display (Prj : Project.View.Object; Full : Boolean := True) is
      use GPR2.Project.Attribute.Set;
      use GPR2.Project.Variable.Set.Set;

      procedure Put_Attributes (Attrs : Attribute.Set.Object);

      --------------------
      -- Put_Attributes --
      --------------------

      procedure Put_Attributes (Attrs : Attribute.Set.Object) is
         Attr : Attribute.Object;
      begin
         for A in Attrs.Iterate (With_Defaults => True) loop
            Attr := Attribute.Set.Element (A);
            Text_IO.Put ("A:   " & String (Attr.Name.Text));

            if Attr.Has_Index then
               if Attr.Is_Any_Index then
                  Text_IO.Put (" ()");
               else
                  Text_IO.Put (" [" & String (Attr.Index.Text)  & ']');
               end if;
            end if;

            Text_IO.Put (" " & (if Attr.Is_Default then '~' else '-') & ">");

            for V of Attribute.Set.Element (A).Values loop
               declare
                  Value : constant Value_Type := V.Text;
                  function No_Last_Slash (Dir : String) return String is
                    (if Dir'Length > 0 and then Dir (Dir'Last) in '\' | '/'
                     then Dir (Dir'First .. Dir'Last - 1) else Dir);
               begin
                  Text_IO.Put
                    (" "
                     & (if No_Last_Slash (Value)
                       = No_Last_Slash (Directories.Current_Directory)
                       then "{Current_Directory}" else Value));
               end;
            end loop;
            Text_IO.New_Line;
         end loop;
      end Put_Attributes;

   begin
      Text_IO.Put (String (Prj.Name) & " ");
      Text_IO.Set_Col (10);
      Text_IO.Put_Line (Prj.Qualifier'Img);

      if Full then
         if Prj.Has_Attributes then
            Put_Attributes (Prj.Attributes);

            for A in Prj.Attributes.Filter ("Object_Dir").Iterate loop
               Text_IO.Put
                 ("A2:  " & String (Attribute.Set.Element (A).Name.Text));
               Text_IO.Put (" ->");

               for V of Attribute.Set.Element (A).Values loop
                  Text_IO.Put (" " & V.Text);
               end loop;
               Text_IO.New_Line;
            end loop;

            for A of Prj.Attributes.Filter ("Object_Dir") loop
               Text_IO.Put_Line ("A3:  " & String (A.Name.Text));
            end loop;

         end if;

         if Prj.Has_Variables then
            for V in Prj.Variables.Iterate loop
               Text_IO.Put ("V:   " & String (Key (V)));
               Text_IO.Put (" ->");

               if Element (V).Kind = Single then
                  Text_IO.Put (" " & Element (V).Value.Text);

               else
                  for Val of Element (V).Values loop
                     Text_IO.Put (" " & Val.Text);
                  end loop;
               end if;
               Text_IO.New_Line;
            end loop;
         end if;

         if Prj.Has_Packages then
            for P of Prj.Packages loop
               Text_IO.Put_Line (String (P.Name));
               if P.Has_Attributes then
                  Put_Attributes (P.Attributes);
               end if;
               if P.Name = Registry.Pack.Compiler then
                  Put_Attributes
                    (P.Attributes
                      (Registry.Attribute.Switches, "Capital.adb"));
               end if;
            end loop;
         end if;
      end if;

   end Display;

   Prj : Project.Tree.Object;
   Ctx : Context.Object;

begin
   Project.Tree.Load (Prj, Create ("demo.gpr"), Ctx);

   Display (Prj.Root_Project);
end Main;
