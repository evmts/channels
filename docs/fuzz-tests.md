Zig Native Fuzz Testing
Overview of Zig’s Fuzz Testing Feature
Zig (as of the bleeding-edge 0.14.0 development branch) includes an integrated, coverage-guided fuzz testing framework as part of its unit test system. This feature is still alpha-quality and under active development[1]. By writing a special kind of test (a fuzz test) and running the build with the --fuzz option, Zig will repeatedly generate random inputs and execute the test to find crashes or assertion failures. Under the hood, Zig uses instrumentation similar to LLVM’s libFuzzer/AFL to guide the input generation based on code coverage[2]. The fuzzing loop runs in-process and will continue until manually stopped or until a failing input is found[3]. Zig even provides a simple web UI for fuzzing: when you run a fuzz test, it starts an HTTP server that shows a live coverage map of the code being fuzzed[4]. (The console output will show an address like http://127.0.0.1:XXXXX for the coverage interface.)
Important: At present, Zig’s native fuzzing is only supported on Linux. Attempts to run zig build test --fuzz on macOS will fail – the current implementation assumes ELF binaries and lacks Mach-O support, so the fuzzer does not work on macOS in Zig 0.14[5][6]. (There is an open issue to add macOS support[7], but until that is resolved, a workaround is needed to fuzz on Mac.) We’ll discuss a common workaround (using Docker) after covering how to write and use fuzz tests.
Writing Fuzz Tests in Zig
Writing a fuzz test in Zig is straightforward and similar to writing a regular unit test, with a slight difference in how input is provided. You need to define a function that will be invoked with random input data, and then register that function as a fuzz test. The function signature should be either fn(input: []const u8) anyerror!void for a stateless fuzz target, or fn(context: ContextType, input: []const u8) anyerror!void if you need some context object. Here’s how you can define and use a fuzz test:
Using std.testing.fuzz: In Zig’s standard library, the std.testing.fuzz function is used to mark a fuzz test. You call it inside a test { ... } block, passing in your fuzz target function (and an optional context value). For example, the default project template (zig init) includes a fuzz test like this:
const std = @import("std");  test "fuzz example" {  const global = struct {  fn testOne(input: []const u8) anyerror!void {  // The fuzzer will try to find an input that makes this condition true:  try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));  }  };  try std.testing.fuzz(global.testOne, .{}); }
<sup><sub>[8] Example fuzz test that fails if the input equals the string "canyoufindme". The fuzzer will generate random byte slices as input until it eventually discovers that exact byte sequence, causing the expect to fail.</sub></sup>
In this example, global.testOne is a function that takes a []const u8 input and asserts that it is not equal to the secret string "canyoufindme". By passing this function to std.testing.fuzz, we tell Zig that this is a fuzz test. When run in fuzzing mode, Zig will repeatedly call testOne with different byte sequences, aiming to break the assertion. (If run normally without --fuzz, this test will just perform one quick random iteration as a smoke test[9].)
Context and state: If your fuzz test needs some state or context for each run, you can provide a context object. For example, Zig’s release notes show a fuzz test where a context string is provided to the fuzz function:
fn findSecret(context: []const u8, input: []const u8) !void {  if (std.mem.eql(u8, context, input))  return error.FoundSecretString; }  test "fuzz example with context" {  // Fuzz will try to make `input` match the context "secret"  try std.testing.fuzz(@as([]const u8, "secret"), findSecret, .{}); }
<sup><sub>[10][11] Using std.testing.fuzz with a context. Here the context is the byte string "secret", and the fuzz function findSecret will error out if the input equals that secret string.</sub></sup>
In this case, std.testing.fuzz(context_value, func, .{}) is used. Zig will ensure the findSecret function (which takes a context and input) is repeatedly called with the given context ("secret") and various inputs. If the input ever matches the context exactly, it returns an error (FoundSecretString), which the fuzzer will detect as a failure. This demonstrates how you can pass in a fixed context or state that the fuzzer should use on every iteration.
Old API note: Earlier in Zig’s development (mid-2024), fuzz tests were written by calling std.testing.fuzzInput() inside a test to get a random input buffer[12]. That API has since changed. In the latest Zig master, std.testing.fuzzInput has been removed. Instead, you wrap your fuzz logic in a function as shown above and pass it to std.testing.fuzz[13]. (So if you encounter older examples using fuzzInput, keep in mind the new approach is different[13].) The examples we provided use the current API on Zig master.
Running Fuzz Tests (Linux)
Once you have written your fuzz tests, you run them via the Zig build system using the --fuzz option. Usually this is done with the command:
zig build test --fuzz
This command tells Zig’s build runner to recompile any test binaries that contain fuzz tests with special instrumentation (-ffuzz) and then launch the fuzzing loop[14]. When you run this, you’ll notice a few things in the output:
Zig will print a line indicating the fuzzing has started and the web interface address. For example:
$ zig build test --fuzz  info: web interface listening at http://127.0.0.1:38239/  info: hint: pass --port 38239 to use this same port next time  [0/1] Fuzzing  └─ foo.bar.example  
<sup><sub>[4] Output from running zig build test --fuzz, showing the local web UI port and that fuzzing has begun on the test case.</sub></sup>
You can open the provided URL in a browser to visualize code coverage in real time as the fuzzer runs[4]. The console also shows the fuzzing progress (e.g. it lists which test is being fuzzed).
By default, zig build test --fuzz will run indefinitely (until you stop it with Ctrl-C) or until a bug is found. You can optionally limit the fuzzing duration. For example, zig build test --fuzz=300s would fuzz for 5 minutes then stop if no issues are found[3]. (You can also specify other formats like an iteration count if supported, but time in seconds is the documented format in the design notes[3].) If you just run zig build test without --fuzz, any fuzz tests will execute only once with a random input (just to ensure they don’t immediately fail)[9].
When a failure is found: If the fuzzer discovers an input that causes an error (for instance, an assertion failure, panic, or returned error in your fuzz function), it will stop and output the details. You’ll typically see a stack trace or panic message indicating what went wrong. For example, one Zig blog post showed how a fuzz test caught an out-of-bounds bug in a tokenizer, resulting in output like:
thread 51449 panic: index out of bounds: index 1, len 1  ../src/tokenizer.zig:60:61: 0x114f818 in tokenizeOne (test)  ../src/tokenizer.zig:133:43: 0x1154962 in test.tokenizer fuzzing (test)  
<sup><sub>[15] Example panic stack trace produced when the fuzzer found a bug (out-of-bounds access) during a fuzz test.</sub></sup>
At this point, the fuzzing stops. The failing input that triggered the issue is saved (Zig will typically save it in the test cache directory, e.g. under .zig-cache/fuzz/ along with coverage data). You can then fix the bug and re-run, or use that input as a regression test or as part of a seed corpus.
No output when all tests pass: Note that if all tests (including fuzz tests) pass without error (within the time/iteration you allowed), Zig’s output might be minimal. By default in recent Zig versions, passing tests don’t print detailed output unless you specify verbosity flags (like --summary all for a summary)[16]. So if the fuzzer doesn’t find any failing case and you stop it, you may just see the progress indication and a clean exit.
macOS Workaround: Running Zig Fuzz Tests via Docker
As mentioned, Zig’s fuzzing is not yet natively available on macOS[5]. However, you can still perform fuzz testing on a Mac by running your tests in a Linux environment (for example, using Docker). The idea is to use a Docker container that has Zig (preferably the same bleeding-edge version) installed, and run zig build test --fuzz inside that container. Here’s how you can do it:
Prepare a Docker image with Zig: Since there is no official Zig Docker image (a point of community discussion[17]), you can create your own. Use a lightweight Linux base (e.g. Alpine or Ubuntu) and install a recent Zig build. One convenient approach is to download a pre-built nightly/master Zig binary for Linux. The Zig website provides nightly builds of the master branch for Linux x86_64 and aarch64. For example, you might download a tarball like zig-linux-x86_64-0.14.0-dev.XXXX+YYYYYYYY.tar.xz. Alternatively, you can install Zig via a package manager or build from source in the container, but downloading the official build is quickest.
Create a Dockerfile: Below is an example Dockerfile that sets up an Ubuntu container with the latest Zig and runs the fuzz tests. You would save this as Dockerfile in your project directory:

# Use an Ubuntu base image FROM ubuntu:22.04  # Install wget (to fetch Zig) and any other needed tools (e.g., clang for linking if needed) RUN apt-get update && apt-get install -y wget clang  # Download and install Zig master build for Linux (x86_64 in this example) # (Replace the URL with the latest build link from ziglang.org) RUN wget https://ziglang.org/builds/zig-linux-x86_64-0.14.0-dev.2915+abcdef123.tar.xz -O /tmp/zig.tar.xz && \  tar -xf /tmp/zig.tar.xz -C /usr/local && \  ln -s /usr/local/zig-linux-x86_64-0.14.0-dev.2915+abcdef123/zig /usr/local/bin/zig  # Set the working directory inside the container and copy the project files WORKDIR /project COPY . /project  # Default command: run the fuzz tests CMD ["zig", "build", "test", "--fuzz"]

Build this image with docker build -t zig-fuzz-env . (from your project directory, where the Dockerfile is). The Dockerfile above downloads a specific Zig nightly build – you should replace the URL with the actual latest build URL (find it on Zig’s download page for master builds). It then copies your project into the image.
Run the container: Once built, run the container interactively, mapping a port for the web UI. For example: 
docker run -it -p 127.0.0.1:5000:5000 zig-fuzz-env
This will drop you into a shell inside the container (if you used an interactive entrypoint), or directly run the fuzz tests (if using the CMD as above, it might start fuzzing immediately). You may want to adjust the --port for the fuzz web UI. Zig by default picks a random port for the web interface; you can fix this by running zig build test --fuzz --port 5000 (for instance)[18]. In Docker, ensure that port is published (-p 5000:5000 as shown).
View results: The fuzzing will run inside the container just as it would on a Linux machine. You can open your browser to http://127.0.0.1:5000 (if you used port 5000) to see the coverage UI. Any crashes or failing inputs will be reported in the container’s console. You can stop the fuzzing with Ctrl-C. If a failure occurs, remember to collect the crashing input from the container (it will be in .zig-cache inside the container filesystem) unless it’s printed directly.
Using Docker in this way allows Mac users to leverage Zig’s native fuzzing by piggybacking on Linux support. The alternative is to run a Linux virtual machine or use a CI system to run fuzz tests on Linux. Until Zig adds native macOS support for fuzzing, containerization is a practical solution. As one Zig contributor noted, “the fuzzer released with 0.14.0 does not work with MacOS”[5] – so running it under Linux is currently the only option if you want to stick with Zig’s built-in fuzzer.
Conclusion and Further Resources
Zig’s native fuzz testing capability is a powerful tool for automatically uncovering edge-case bugs in your code. To summarize the key steps: write a fuzz test by calling std.testing.fuzz with a suitable function (and optional context), then execute zig build test --fuzz on a Linux environment to run the fuzzer. The fuzzer will continuously generate inputs and track coverage, giving you real-time feedback via a web UI and stopping when a bug is found or when you terminate the run. This feature is quite new – labeled as “alpha” in the 0.14 release notes[1] – so expect improvements and changes as Zig evolves (for example, more advanced input generation and eventually macOS support are on the roadmap[19][7]).
For more information and examples, you can refer to the Zig 0.14.0 release notes (section on the Fuzzer)[1][11], the Zig documentation and standard library (which will include any updates on the fuzz testing API), and community write-ups. A useful community example is the blog post “Using Zig’s fuzzer” which demonstrates a simple fuzz test and how a bug was found in under a minute[15]. Keep an eye on Zig’s issue tracker for developments like enhanced fuzz algorithms[19] and macOS support. Happy fuzzing with Zig’s native tools!
Sources:
Zig 0.14.0 Release Notes – Integrated Fuzzer description and example[1][11]
Ziggit Forum – “Fuzz testing example?” (usage of std.testing.fuzz in Zig master)[8][20]
Ziggit Forum – “How do I fuzz something?” (new fuzz API vs old fuzzInput)[13][21]
PhoenixK’s Blog – “Using Zig’s fuzzer” (demonstration of fuzz test and output)[12][15]
Zig Issue #20986 – “fuzz testing: support macOS” (Mac ELF/Mach-O limitation)[6][22]
Ziggit Forum – “Error: no fuzz tests found” (build.zig integration note)[23][24]
Ziggit Forum – “How to trigger the fuzzer loop?” (confirmation of Mac not supported)[5]
Zig Issue #20702 – “integrated fuzz testing” (design of zig build --fuzz CLI)[3]

[1] [4] [10] [11] [14] 0.14.0 Release Notes ⚡ The Zig Programming Language
https://ziglang.org/download/0.14.0/release-notes.html
[2] [3] integrated fuzz testing · Issue #20702 · ziglang/zig · GitHub
https://github.com/ziglang/zig/issues/20702
[5] How to trigger the fuzzer loop? - Help - Ziggit
https://ziggit.dev/t/how-to-trigger-the-fuzzer-loop/10042
[6] [7] [18] [22] fuzz testing: support macOS · Issue #20986 · ziglang/zig · GitHub
https://github.com/ziglang/zig/issues/20986
[8] [19] [20] Fuzz testing example? - Help - Ziggit
https://ziggit.dev/t/fuzz-testing-example/7590
[9] `std.testing.fuzzInput`: introduce a corpus option · Issue #20814 · ziglang/zig · GitHub
https://github.com/ziglang/zig/issues/20814
[12] [15] Using Zig’s fuzzer / blog.
https://phoenixk.net/zig-fuzz
[13] [21] How do I fuzz something? - Help - Ziggit
https://ziggit.dev/t/how-do-i-fuzz-something/6866
[16] Can anyone zig build test ? It fails to run for me on both Macos and ...
https://www.reddit.com/r/Zig/comments/17m9bhc/can_anyone_zig_build_test_it_fails_to_run_for_me/
[17] ziglang/docker-zig: Dockerfile for zig programming language - GitHub
https://github.com/ziglang/docker-zig
[23] [24] Error: no fuzz tests found - Help - Ziggit
https://ziggit.dev/t/error-no-fuzz-tests-found/9802
