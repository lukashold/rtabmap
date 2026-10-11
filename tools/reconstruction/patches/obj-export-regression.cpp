// Kantura OpenMVS OBJ regression, distributed under the repository license.
// This calls the actual compiled exporter, not an engine mock or text check.
#include "libs/MVS/Common.h"
#include "libs/MVS/Mesh.h"
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <set>
#include <map>
#include <cmath>

using namespace MVS;

static std::string Read(const std::string& name) {
    std::ifstream input(name);
    if (!input.good()) throw std::runtime_error("Missing exported file: " + name);
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}

static size_t Lines(const std::string& text, const std::string& prefix) {
    std::istringstream stream(text);
    std::string line;
    size_t count = 0;
    while (std::getline(stream, line)) if (line.compare(0, prefix.size(), prefix) == 0) ++count;
    return count;
}

static void Check(const bool condition, const char* message) {
    // Release builds disable ASSERT; these checks must remain active.
    if (!condition) throw std::runtime_error(message);
}

static void Export(const unsigned atlasCount) {
    Mesh mesh;
    mesh.vertices.emplace_back(0.f, 0.f, 0.f);
    mesh.vertices.emplace_back(1.f, 0.f, 0.f);
    mesh.vertices.emplace_back(0.f, 1.f, 0.f);
    mesh.vertices.emplace_back(1.f, 1.f, 0.f);
    mesh.faces.emplace_back(0, 1, 2);
    mesh.faces.emplace_back(1, 3, 2);
    for (unsigned i = 0; i < 2; ++i) {
        mesh.faceTexcoords.emplace_back(0.f, 0.f);
        mesh.faceTexcoords.emplace_back(3.f, 0.f);
        mesh.faceTexcoords.emplace_back(0.f, 3.f);
    }
    for (unsigned i = 0; i < atlasCount; ++i) {
        Image8U3 texture;
        texture.create(4, 4);
        texture.setTo(cv::Scalar(30, 160, 220));
        mesh.texturesDiffuse.emplace_back(texture);
    }
    if (atlasCount == 2) {
        mesh.faceTexindices.emplace_back(0);
        mesh.faceTexindices.emplace_back(1);
    }
    // SceneTexture releases this array when atlasCount==1. The old exporter
    // dereferenced it anyway and segfaulted after otherwise valid texturing.
    Check(atlasCount == 2 || mesh.faceTexindices.empty(), "Single atlas must use implicit texture zero");
    const std::string name = "/tmp/kantura-obj-regression/atlas" + std::to_string(atlasCount);
    Check(mesh.SaveOBJ((name + ".obj").c_str()), "OBJ export failed");
    const std::string obj = Read(name + ".obj");
    Check(Lines(obj, "v ") == 4, "Export changed vertex count");
    Check(Lines(obj, "vt ") == 6, "Texture coordinates missing");
    Check(Lines(obj, "f ") == 2, "Export lost or duplicated faces");
    Check(Lines(obj, "usemtl ") == atlasCount, "Wrong face/material grouping");
    std::istringstream geometry(obj);
    std::string line, material;
    std::set<unsigned> usedVertices, usedUVs;
    std::map<std::string, unsigned> materialFaces;
    while (std::getline(geometry, line)) {
        std::istringstream values(line);
        std::string kind;
        values >> kind;
        if (kind == "usemtl") values >> material;
        if (kind == "vt") {
            double u = -1, v = -1;
            values >> u >> v;
            Check(std::isfinite(u) && std::isfinite(v) && u >= 0 && u <= 1 && v >= 0 && v <= 1,
                  "Invalid normalized texture coordinates");
        }
        if (kind != "f") continue;
        Check(!material.empty(), "Face missing material reference");
        ++materialFaces[material];
        for (unsigned corner = 0; corner < 3; ++corner) {
            std::string reference;
            values >> reference;
            const size_t slash = reference.find('/');
            Check(slash != std::string::npos, "Face missing UV index");
            const unsigned vertex = std::stoul(reference.substr(0, slash));
            const unsigned uv = std::stoul(reference.substr(slash + 1));
            Check(vertex >= 1 && vertex <= 4 && uv >= 1 && uv <= 6, "Face index out of bounds");
            usedVertices.insert(vertex);
            usedUVs.insert(uv);
        }
    }
    Check(usedVertices.size() == 4 && usedUVs.size() == 6, "Export lost geometry or corner UVs");
    Check(materialFaces.size() == atlasCount, "An atlas has no faces");
    if (atlasCount == 2) for (const auto& item : materialFaces)
        Check(item.second == 1, "Face assigned to the wrong atlas");
    const std::string mtl = Read(name + ".mtl");
    Check(Lines(mtl, "newmtl ") == atlasCount, "Missing material");
    Check(Lines(mtl, "map_Kd ") == atlasCount, "Missing diffuse texture map");
    std::istringstream stream(mtl);
    while (std::getline(stream, line)) {
        if (line.compare(0, 7, "map_Kd ") == 0) {
            Image8U3 decoded;
            Check(decoded.Load(("/tmp/kantura-obj-regression/" + line.substr(7)).c_str()) && decoded.cols == 4 && decoded.rows == 4,
                  "Missing or invalid texture image");
        }
    }
}

int main() {
    OPEN_LOG();
    OPEN_LOGCONSOLE();
    MVS::Initialize("KanturaOBJRegression", 1, -1);
    try {
        Export(1);
        Export(2);
    } catch (const std::exception& error) {
        std::cerr << error.what() << std::endl;
        return EXIT_FAILURE;
    }
    MVS::Finalize();
    CLOSE_LOGCONSOLE();
    CLOSE_LOG();
    return EXIT_SUCCESS;
}
