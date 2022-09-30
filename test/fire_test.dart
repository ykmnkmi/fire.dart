// This isn't using package:test due to some version related
// weirdness and to minimize the amount of dependencies.
void main() {
  _TestSuite.all();
}

// TODO cache dir create a fire cache dir.
// TODO cache dir delete that fire cache dir.
// TODO cache dir create an empty package
abstract class _TestSuite {
  static void all() {
    can_reload_programs();
    programs_that_fail_to_compile_do_not_cause_a_crash();
    programs_that_have_been_repaired_do_reload_correctly();
  }

  static void can_reload_programs() {
    // TODO simple test.
  }

  static void programs_that_fail_to_compile_do_not_cause_a_crash() {
    // TODO load a valid program, then an invalid one
  }

  static void programs_that_have_been_repaired_do_reload_correctly() {
    // TODO load a valid program, then an invalid one and then a valid one again.
  }
}
