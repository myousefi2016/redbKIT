import vtk
import numpy as np

def vtkUnstructuredReader(filename):
    reader = vtk.vtkXMLUnstructuredGridReader()
    reader.SetFileName(filename)
    reader.Update()
    
    ug = reader.GetOutput()

    return ug

mesh = vtkUnstructuredReader('C0001.vtu')

gmsh_output = []

gmsh_output.append('$MeshFormat')
gmsh_output.append('2.2 0 8')
gmsh_output.append('$EndMeshFormat')

gmsh_output.append('$Nodes')
gmsh_output.append(str(mesh.GetNumberOfPoints()))

for i in range(mesh.GetNumberOfPoints()):
    p = mesh.GetPoint(i)
    gmsh_output.append(str(i+1)+' '+str(p[0])+' '+str(p[1])+' '+str(p[2]))

gmsh_output.append('$EndNodes')

gmsh_output.append('$Elements')
gmsh_output.append(str(mesh.GetNumberOfCells()))

gmshCellTypes = {5:2,10:4}

for i in range(mesh.GetNumberOfCells()):

    cell = mesh.GetCell(i)

    nPoints = cell.GetNumberOfPoints()

    cellType = cell.GetCellType()

    pointIds = cell.GetPointIds()

    cid = mesh.GetCellData().GetScalars('ObjectId').GetValue(i)

    if nPoints == 3:
        gmsh_output.append(str(i+1)+' '+str(gmshCellTypes[cellType])+' '+str(2)+' '+str(cid)+' '+str(cid)+' '+str(pointIds.GetId(0)+1)+' '+str(pointIds.GetId(1)+1)+' '+str(pointIds.GetId(2)+1))
    elif nPoints == 4:
        gmsh_output.append(str(i+1)+' '+str(gmshCellTypes[cellType])+' '+str(2)+' '+str(cid)+' '+str(cid)+' '+str(pointIds.GetId(0)+1)+' '+str(pointIds.GetId(1)+1)+' '+str(pointIds.GetId(2)+1)+' '+str(pointIds.GetId(3)+1))

gmsh_output.append('$EndElements')

with open('C0001.msh', 'w') as f:
    for j,item in enumerate(gmsh_output):
     if j < len(gmsh_output) - 1:
        f.write("%s\n" % item)
     else:
        f.write("%s" % item)
