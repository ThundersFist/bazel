"""Template for the build file used in android_sdk_repository."""
# Copyright 2016 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

def create_android_sdk_rules(
    name,
    build_tools_version,
    build_tools_directory,
    api_levels,
    default_api_level):
  """Generate android_sdk rules for the API levels in the Android SDK.

  Args:
    name: string, the name of the repository being generated.
    build_tools_version: string, the version of Android's build tools to use.
    build_tools_directory: string, the directory name of the build tools in
        sdk's build-tools directory.
    api_levels: list of ints, the API levels from which to get android.jar
        et al. and create android_sdk rules.
    default_api_level: int, the API level to alias the default sdk to if
        --android_sdk is not specified on the command line.
  """

  # This filegroup is used to pass the contents of the SDK to the Android
  # integration tests. We need to glob because not all of these folders ship
  # with the Android SDK, some need to be installed through the SDK Manager.
  # Since android_sdk_repository function generates BUILD files, we do not want
  # to include those because the integration test would fail when it tries to
  # regenerate those BUILD files because the Bazel Sandbox does not allow
  # overwriting existing files.
  native.filegroup(
      name = "files",
      srcs = native.glob([
          "add-ons",
          "build-tools",
          "extras",
          "platforms",
          "platform-tools",
          "sources",
          "system-images",
          "tools",
      ], exclude_directories = 0),
  )

  for api_level in api_levels:
    if api_level >= 23:
      # Android 23 removed most of org.apache.http from android.jar and moved it
      # to a separate jar.
      native.java_import(
          name = "org_apache_http_legacy-%d" % api_level,
          jars = ["platforms/android-%d/optional/org.apache.http.legacy.jar" % api_level]
      )

    native.android_sdk(
        name = "sdk-%d" % api_level,
        build_tools_version = build_tools_version,
        proguard = ":proguard_binary",
        aapt = ":aapt_binary",
        dx = ":dx_binary",
        main_dex_list_creator = ":main_dex_list_creator",
        adb = "platform-tools/adb",
        framework_aidl = "platforms/android-%d/framework.aidl" % api_level,
        aidl = ":aidl_binary",
        android_jar = "platforms/android-%d/android.jar" % api_level,
        shrinked_android_jar = "platforms/android-%d/android.jar" % api_level,
        annotations_jar = "tools/support/annotations.jar",
        main_dex_classes = "build-tools/%s/mainDexClasses.rules" % build_tools_directory,
        apksigner = ":apksigner",
        zipalign = ":zipalign_binary",
        resource_extractor = "@bazel_tools//tools/android:resource_extractor",
    )

  native.alias(
      name = "org_apache_http_legacy",
      actual = ":org_apache_http_legacy-%d" % default_api_level,
  )

  native.alias(
      name = "sdk",
      actual = ":sdk-%d" % default_api_level,
  )

  native.java_import(
      name = "proguard_import",
      jars = ["tools/proguard/lib/proguard.jar"]
  )

  native.java_binary(
      name = "proguard_binary",
      main_class = "proguard.ProGuard",
      runtime_deps = [":proguard_import"]
  )

  native.java_binary(
      name = "apksigner",
      main_class = "com.android.apksigner.ApkSignerTool",
      runtime_deps = ["build-tools/%s/lib/apksigner.jar" % build_tools_directory],
  )

  native.filegroup(
      name = "build_tools_libs",
      srcs = native.glob([
          "build-tools/%s/lib/**" % build_tools_directory,
          # Build tools version 24.0.0 added a lib64 folder.
          "build-tools/%s/lib64/**" % build_tools_directory,
      ])
  )

  for tool in ["aapt", "aidl", "zipalign"]:
    native.genrule(
        name = tool + "_runner",
        outs = [tool + "_runner.sh"],
        srcs = [],
        cmd  = "\n".join([
            "cat > $@ << 'EOF'",
            "#!/bin/bash",
            "set -eu",
            # The tools under build-tools/VERSION require the libraries under build-tools/VERSION/lib,
            # so we can't simply depend on them as a file like we do with aapt.
            "SDK=$${0}.runfiles/%s" % name,
            "exec $${SDK}/build-tools/%s/%s $$*" % (build_tools_directory, tool),
            "EOF\n"]),
    )

    native.sh_binary(
        name = tool + "_binary",
        srcs = [tool + "_runner.sh"],
        data = [
            ":build_tools_libs",
            "build-tools/%s/%s" % (build_tools_directory, tool)
        ],
    )

  native.sh_binary(
      name = "fail",
      srcs = ["fail.sh"])

  native.genrule(
      name = "generate_fail_sh",
      srcs = [],
      outs = ["fail.sh"],
      cmd = "echo -e '#!/bin/bash\\nexit 1' >> $@; chmod +x $@",
  )


  native.genrule(
      name = "main_dex_list_creator_source",
      srcs = [],
      outs = ["main_dex_list_creator.sh"],
      cmd = "\n".join(["cat > $@ <<'EOF'",
            "#!/bin/bash",
            "",
            "MAIN_DEX_LIST=$$1",
            "STRIPPED_JAR=$$2",
            "JAR=$$3",
            "" +
            "DIRNAME=$$(dirname $$0)",
            "JAVA_BINARY=TBD/main_dex_list_creator_java",  # Proper runfiles path comes here
            "$$JAVA_BINARY $$STRIPPED_JAR $$JAR > $$MAIN_DEX_LIST",
            "exit $$?",
            "",
            "EOF\n"]),
  )

  native.sh_binary(
      name = "main_dex_list_creator",
      srcs = ["main_dex_list_creator.sh"],
      data = [":main_dex_list_creator_java"],
  )

  native.java_binary(
      name = "main_dex_list_creator_java",
      main_class = "com.android.multidex.ClassReferenceListBuilder",
      runtime_deps = [":dx_jar_import"],
  )

  native.java_binary(
      name = "dx_binary",
      main_class = "com.android.dx.command.Main",
      runtime_deps = [":dx_jar_import"],
  )

  native.filegroup(
      name = "dx_jar",
      srcs = ["build-tools/%s/lib/dx.jar" % build_tools_directory],
  )

  native.java_import(
      name = "dx_jar_import",
      jars = [":dx_jar"],
  )


TAGDIR_TO_TAG_MAP = {
    "google_apis": "google",
    "default": "android",
    "android-tv": "tv",
    "android-wear": "wear",
}


ARCHDIR_TO_ARCH_MAP = {
    "x86": "x86",
    "armeabi-v7a": "arm",
}


def create_system_images_filegroups(system_image_dirs):
  """Generate filegroups for the system images in the Android SDK.

  Args:
    system_image_dirs: list of strings, the directories containing system image
        files to be used to create android_device rules.
  """

  # These images will need to be updated as Android releases new system images.
  # We are intentionally not adding future releases because there is no
  # guarantee that they will work out of the box. Supported system images should
  # be added here once they have been confirmed to work with the Bazel Android
  # testing infrastructure.
  system_images = [(tag, api, arch)
                   for tag in ["android", "google"]
                   for api in [10] + range(15, 20) + range(21, 27)
                   for arch in ("x86", "arm")]
  tv_images = [("tv", api, arch)
               for api in range(21, 25) for arch in ("x86", "arm")]
  wear_images = [("wear", api, "x86")
                 for api in range(20, 26)] + [("wear", api, "arm")
                                              for api in range(24, 26)]
  supported_system_images = system_images + tv_images + wear_images

  installed_system_images_dirs = {}
  for system_image_dir in system_image_dirs:
    apidir, tagdir, archdir = system_image_dir.split("/")[1:]
    api = int(apidir.split("-")[1])  # "android-24" --> 24
    if tagdir not in TAGDIR_TO_TAG_MAP:
      continue
    tag = TAGDIR_TO_TAG_MAP[tagdir]
    if archdir not in ARCHDIR_TO_ARCH_MAP:
      continue
    arch = ARCHDIR_TO_ARCH_MAP[archdir]
    if (tag, api, arch) in supported_system_images:
      name = "emulator_images_%s_%s_%s" % (tag, api, arch)
      installed_system_images_dirs[name] = system_image_dir
    else:
      # TODO(bazel-team): If the user has an unsupported system image installed,
      # should we print a warning? This includes all 64-bit system-images.
      pass

  for (tag, api, arch) in supported_system_images:
    name = "emulator_images_%s_%s_%s" % (tag, api, arch)
    if name in installed_system_images_dirs:
      system_image_dir = installed_system_images_dirs[name]
      # For supported system images that exist in /sdk/system-images/, we
      # create a filegroup with their contents.
      native.filegroup(
          name = name,
          srcs = native.glob([
              "%s/**" % system_image_dir,
          ]),
      )
      native.filegroup(
          name = "%s_qemu2_extra" % name,
          srcs = native.glob(["%s/kernel-ranchu" % system_image_dir]),
      )
    else:
      # For supported system images that are not installed in the SDK, we
      # create a "poison pill" genrule to display a helpful error message to
      # a user who attempts to run a test against an android_device that
      # they don't have the system image for installed.
      native.genrule(
          name = name,
          outs = [
              # Necessary so that the build doesn't fail in analysis because
              # android_device expects a file named source.properties.
              "poison_pill_for_%s/source.properties" % name,
          ],
          cmd = """echo \
          This rule requires that the Android SDK used by Bazel has the \
          following system image installed: %s. Please install this system \
          image through the Android SDK Manager and try again. ; \
          exit 1
          """ % name,
      )
      native.filegroup(
          name = "%s_qemu2_extra" % name,
          srcs = [],
      )
