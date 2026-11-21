# A Linux recorder for the Godot client: Godot at the pinned version, a virtual display (Xvfb), a software renderer (Mesa
# llvmpipe), Node and ffmpeg. Clips from this image do not depend on a GPU or on the computer that records them.
#
#   docker build -f godot/tools/Dockerfile -t agent-workshop-godot-recorder .          # from the root of the repository
#   docker run --rm --init -v "<repo>/godot/out:/app/godot/out" agent-workshop-godot-recorder --scene tour
#   docker run --rm --init -v "<repo>/godot/out:/app/godot/out" agent-workshop-godot-recorder --scene multi --stills 7,22.5
#
# The arguments after the image name go to tools/record.mjs (see its top). The clips and stills are written to /app/godot/out.
# To check that two runs agree, run determinism.mjs in the image:
#   docker run --rm --init --entrypoint xvfb-run agent-workshop-godot-recorder -a node tools/determinism.mjs --scene session
# Podman takes the same commands.
#
# STATUS: see godot/README.md for what was run. The Godot download is checked against the hash in tools/get-godot.mjs.
# The software renderer may give other pixels than a GPU: only clips from the same image can be compared with each other.
FROM node:24-bookworm-slim

# xvfb and xauth: the virtual display. libgl1-mesa-dri and libegl1: Mesa, with its software renderer. The X libraries are the ones that the
# Godot binary loads. ffmpeg: libx264 and AAC. unzip: get-godot.mjs unpacks the editor with it. ca-certificates: the download.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates unzip xvfb xauth ffmpeg \
      libgl1 libglx-mesa0 libgl1-mesa-dri libegl1 libx11-6 libxcursor1 libxext6 libxi6 libxinerama1 libxrandr2 libxrender1 libxkbcommon0 libfontconfig1 libasound2 \
 && rm -rf /var/lib/apt/lists/*

# Mesa draws with the CPU. The virtual display has 24 bits of colour.
ENV LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    MESA_GL_VERSION_OVERRIDE=4.5 \
    NODE_ENV=production

WORKDIR /app/godot
# The editor first, so that a change in the project does not download it again.
COPY godot/GODOT_VERSION ./GODOT_VERSION
COPY godot/tools/get-godot.mjs godot/tools/godot-path.mjs ./tools/
RUN node tools/get-godot.mjs

# The project, then one import so that the image starts with a cache of the imported files.
COPY godot/ ./
RUN "$(ls .editor/*/Godot_v*_linux.x86_64)" --headless --path . --import

VOLUME /app/godot/out
ENTRYPOINT ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", "node", "tools/record.mjs"]
