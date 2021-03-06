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

with Ada.Text_IO;
with GPR2.Project.View;
with GPR2.Project.Tree;
with GPR2.Project.Attribute.Set;
with GPR2.Project.Variable.Set;
with GPR2.Context;

procedure Main is

   use Ada;
   use GPR2;
   use GPR2.Project;

   procedure Display (Prj : Project.View.Object; Full : Boolean := True);

   procedure Changed_Callback (Prj : Project.View.Object);

   ----------------------
   -- Changed_Callback --
   ----------------------

   procedure Changed_Callback (Prj : Project.View.Object) is
   begin
      Text_IO.Put_Line (">>> Changed_Callback for " & Value (Prj.Path_Name));
   end Changed_Callback;

   -------------
   -- Display --
   -------------

   procedure Display (Prj : Project.View.Object; Full : Boolean := True) is
      use GPR2.Project.Attribute.Set;
      use GPR2.Project.Variable.Set.Set;
   begin
      Text_IO.Put (Prj.Name & " ");
      Text_IO.Set_Col (10);
      Text_IO.Put_Line (Prj.Qualifier'Img);

      if Full then
         if Prj.Has_Attributes then
            for A in Prj.Attributes.Iterate loop
               Text_IO.Put ("A:   " & String (Element (A).Name));
               Text_IO.Put (" -> ");

               for V of Element (A).Values loop
                  Text_IO.Put (V & " ");
               end loop;
               Text_IO.New_Line;
            end loop;
         end if;

         if Prj.Has_Variables then
            for V in Prj.Variables.Iterate loop
               Text_IO.Put ("V:   " & String (Key (V)));
               Text_IO.Put (" -> ");
               Text_IO.Put (String (Element (V).Value));
               Text_IO.New_Line;
            end loop;
         end if;
         Text_IO.New_Line;
      end if;
   end Display;

   Prj1, Prj2 : Project.Tree.Object;
   Ctx        : Context.Object;

begin
   Prj1 := Project.Tree.Load (Create ("demo.gpr"));
   Prj2 := Project.Tree.Load (Create ("demo.gpr"));

   Ctx := Prj1.Context;
   Ctx.Include ("OS", "Linux");
   Prj1.Set_Context (Ctx, Changed_Callback'Access);

   Ctx := Prj2.Context;
   Ctx.Include ("OS", "Windows");
   Prj2.Set_Context (Ctx, Changed_Callback'Access);

   Display (Prj1.Root_Project);
   Display (Prj2.Root_Project);

   Ctx.Clear;
   Ctx.Include ("OS", "Linux-2");
   Prj2.Set_Context (Ctx, Changed_Callback'Access);
   Display (Prj2.Root_Project);

   --  Iterator

   Text_IO.Put_Line ("**************** Iterator Prj1");

   for C in Project.Tree.Iterate (Prj1, Kind => I_Project + I_Imported) loop
      Display (Project.Tree.Element (C), Full => False);
      if Project.Tree.Is_Root (C) then
         Text_IO.Put_Line ("   is root");
      end if;
   end loop;

   Text_IO.Put_Line ("**************** Iterator Prj2");

   for C in Project.Tree.Iterate (Prj2) loop
      Display (Project.Tree.Element (C), Full => False);
   end loop;

   Text_IO.Put_Line ("**************** Iterator Prj3");

   for C in Project.Tree.Iterate (Prj2, Filter => F_Library) loop
      Display (Project.Tree.Element (C), Full => False);
   end loop;

   Text_IO.Put_Line ("**************** Iterator Prj4");

   for P of Prj2 loop
      Display (P, Full => False);
   end loop;
end Main;
