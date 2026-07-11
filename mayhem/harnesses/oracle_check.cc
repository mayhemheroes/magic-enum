// oracle_check.cc — behavioral oracle for magic_enum; used by mayhem/test.sh.
// Calls the reflection API with KNOWN enum values and PRINTS the results;
// test.sh greps for the expected strings.  A no-op / exit(0) patch emits
// nothing → all greps fail → oracle exits non-zero.
#include <iostream>
#include <string>
#include <magic_enum.hpp>

enum class Color { RED = 1, GREEN = 2, BLUE = 3 };
enum class Dir   { NORTH = 10, SOUTH = 20 };

int main() {
    // enum_name: integer → string
    std::cout << "name(RED)="   << magic_enum::enum_name(Color::RED)   << "\n";
    std::cout << "name(GREEN)=" << magic_enum::enum_name(Color::GREEN) << "\n";
    std::cout << "name(BLUE)="  << magic_enum::enum_name(Color::BLUE)  << "\n";

    // enum_cast: string → enum value  (prints the integer value)
    auto r = magic_enum::enum_cast<Color>("RED");
    std::cout << "cast(RED)="   << (r.has_value() ? static_cast<int>(*r) : -1) << "\n";
    auto g = magic_enum::enum_cast<Color>("GREEN");
    std::cout << "cast(GREEN)=" << (g.has_value() ? static_cast<int>(*g) : -1) << "\n";

    // enum_cast: integer → enum
    auto c2 = magic_enum::enum_cast<Color>(2);
    std::cout << "cast(2)=" << (c2.has_value() ? magic_enum::enum_name(*c2) : "none") << "\n";

    // enum_count
    std::cout << "count(Color)=" << magic_enum::enum_count<Color>() << "\n";
    std::cout << "count(Dir)="   << magic_enum::enum_count<Dir>()   << "\n";

    // enum_contains
    std::cout << "contains(3)=" << (magic_enum::enum_contains<Color>(3) ? "yes" : "no") << "\n";
    std::cout << "contains(99)=" << (magic_enum::enum_contains<Color>(99) ? "yes" : "no") << "\n";

    return 0;
}
