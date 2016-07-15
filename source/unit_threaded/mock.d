module unit_threaded.mock;

import unit_threaded.should: fail;
import std.traits;
import std.typecons;

version(unittest) {
    import unit_threaded.asserts;
    import unit_threaded.should;
}


alias Identity(alias T) = T;

private string implMixinStr(T)() {
    import std.array: join;

    string[] lines;

    foreach(m; __traits(allMembers, T)) {

        alias member = Identity!(__traits(getMember, T, m));

        static if(__traits(isAbstractFunction, member)) {

            enum parameters = Parameters!member.stringof;
            enum returnType = ReturnType!member.stringof;

            static if(is(ReturnType!member == void))
                enum returnDefault = "";
            else
                enum returnDefault = `    return ` ~ returnType ~ ".init;";

            lines ~= `override ` ~ returnType ~ " " ~ m ~ typeAndArgsParens!(Parameters!member) ~ ` {`;
            lines ~= `    calledFuncs ~= "` ~ m ~ `";`;
            lines ~= `    calledValues ~= tuple` ~ argNamesParens(arity!member) ~ `.to!string;`;
            lines ~= returnDefault;
            lines ~= `}`;
            lines ~= "";
        }
    }

    return lines.join("\n");
}

private string argNamesParens(int N) @safe pure {
    return "(" ~ argNames(N) ~ ")";
}

private string argNames(int N) @safe pure {
    import std.range;
    import std.algorithm;
    import std.conv;
    return iota(N).map!(a => "arg" ~ a.to!string).join(", ");
}

private string typeAndArgsParens(T...)() {
    import std.array;
    import std.conv;
    string[] parts;
    foreach(i, t; T)
        parts ~= T[i].stringof ~ " arg" ~ i.to!string;
    return "(" ~ parts.join(", ") ~ ")";
}

mixin template MockImplCommon() {
    bool verified;
    string[] expectedFuncs;
    string[] calledFuncs;
    string[] expectedValues;
    string[] calledValues;

    void expect(string funcName, V...)(V values) @safe pure {
        import std.conv: to;
        import std.typecons: tuple;

        expectedFuncs ~= funcName;
        static if(V.length > 0)
            expectedValues ~= tuple(values).to!string;
        else
            expectedValues ~= "";
    }

    void expectCalled(string func, string file = __FILE__, ulong line = __LINE__, V...)(V values) {
        expect!func(values);
        verify(file, line);
    }

    void verify(string file = __FILE__, ulong line = __LINE__) @safe pure {
        import std.range;
        import std.conv;

        if(verified)
            fail("Mock already verified", file, line);

        verified = true;

        for(int i = 0; i < expectedFuncs.length; ++i) {

            if(i >= calledFuncs.length)
                fail("Expected nth " ~ i.to!string ~ " call to " ~ expectedFuncs[i] ~ " did not happen", file, line);

            if(expectedFuncs[i] != calledFuncs[i])
                fail("Expected nth " ~ i.to!string ~ " call to " ~ expectedFuncs[i] ~ " but got " ~ calledFuncs[i] ~
                     " instead",
                     file, line);

            if(expectedValues[i] != calledValues[i] && expectedValues[i] != "")
                throw new UnitTestException([expectedFuncs[i] ~ " was called with unexpected " ~ calledValues[i],
                                             " ".repeat.take(expectedFuncs[i].length + 4).join ~
                                             "instead of the expected " ~ expectedValues[i]] ,
                                            file, line);
        }
    }
}

struct Mock(T) {

    private MockAbstract _impl;
    alias _impl this;

    class MockAbstract: T {
        import std.conv: to;
        //pragma(msg, implMixinStr!T);
        mixin(implMixinStr!T);
        mixin MockImplCommon;
    }

    ~this() pure @safe {
        if(!verified) verify;
    }
}

auto mock(T)() {
    auto m = Mock!T();
    m._impl = new Mock!T.MockAbstract;
    return m;
}


@("mock interface positive test no params")
@safe pure unittest {
    interface Foo {
        int foo(int, string) @safe pure;
        void bar() @safe pure;
    }

    int fun(Foo f) {
        return 2 * f.foo(5, "foobar");
    }

    auto m = mock!Foo;
    m.expect!"foo";
    fun(m);
}

@("mock interface positive test with params")
@safe pure unittest {
    import unit_threaded.asserts;

    interface Foo {
        int foo(int, string) @safe pure;
        void bar() @safe pure;
    }

    int fun(Foo f) {
        return 2 * f.foo(5, "foobar");
    }

    {
        auto m = mock!Foo;
        m.expect!"foo"(5, "foobar");
        fun(m);
    }

    {
        auto m = mock!Foo;
        m.expect!"foo"(6, "foobar");
        fun(m);
        assertExceptionMsg(m.verify,
                           "    source/unit_threaded/mock.d:123 - foo was called with unexpected Tuple!(int, string)(5, \"foobar\")\n"
                           "    source/unit_threaded/mock.d:123 -        instead of the expected Tuple!(int, string)(6, \"foobar\")");
    }

    {
        auto m = mock!Foo;
        m.expect!"foo"(5, "quux");
        fun(m);
        assertExceptionMsg(m.verify,
                           "    source/unit_threaded/mock.d:123 - foo was called with unexpected Tuple!(int, string)(5, \"foobar\")\n"
                           "    source/unit_threaded/mock.d:123 -        instead of the expected Tuple!(int, string)(5, \"quux\")");
    }
}


@("mock interface negative test")
@safe pure unittest {
    interface Foo {
        int foo(int, string) @safe pure;
    }

    auto m = mock!Foo;
    m.expect!"foo";
    m.verify.shouldThrowWithMessage("Expected nth 0 call to foo did not happen");
}

// can't be in the unit test itself
version(unittest)
private class Class {
    abstract int foo(int, string) @safe pure;
    final int timesTwo(int i) @safe pure nothrow const { return i * 2; }
    int timesThree(int i) @safe pure nothrow const { return i * 3; }
}

@("mock class positive test")
@safe pure unittest {

    int fun(Class f) {
        return 2 * f.foo(5, "foobar");
    }

    auto m = mock!Class;
    m.expect!"foo";
    fun(m);
}


@("mock interface multiple calls")
@safe pure unittest {
    interface Foo {
        int foo(int, string) @safe pure;
        int bar(int) @safe pure;
    }

    void fun(Foo f) {
        f.foo(3, "foo");
        f.bar(5);
        f.foo(4, "quux");
    }

    auto m = mock!Foo;
    m.expect!"foo"(3, "foo");
    m.expect!"bar"(5);
    m.expect!"foo"(4, "quux");
    fun(m);
    m.verify;
}

@("interface expectCalled")
@safe pure unittest {
    interface Foo {
        int foo(int, string) @safe pure;
        void bar() @safe pure;
    }

    int fun(Foo f) {
        return 2 * f.foo(5, "foobar");
    }

    auto m = mock!Foo;
    fun(m);
    m.expectCalled!"foo";
}

auto mock() {
    struct Mock {

        private MockImpl* _impl;
        alias _impl this;

        static struct MockImpl {

            mixin MockImplCommon;

            void opDispatch(string funcName, V...)(V values) {
                import std.conv: to;
                import std.typecons: tuple;
                calledFuncs ~= funcName;
                calledValues ~= tuple(values).to!string;
            }
        }
    }

    Mock m;
    m._impl = new Mock.MockImpl;
    return m;
}


@("mock struct positive")
@safe pure unittest {
    void fun(T)(T t) {
        t.foobar;
    }
    auto m = mock;
    m.expect!"foobar";
    fun(m);
    m.verify;
}

@("mock struct negative")
@safe pure unittest {
    auto m = mock;
    m.expect!"foobar";
    assertExceptionMsg(m.verify,
                       "    source/unit_threaded/mock.d:123 - Expected nth 0 call to foobar did not happen\n");

}


@("mock struct values positive")
@safe pure unittest {
    void fun(T)(T t) {
        t.foobar(2, "quux");
    }

    auto m = mock;
    m.expect!"foobar"(2, "quux");
    fun(m);
    m.verify;
}

@("mock struct values negative")
@safe pure unittest {
    void fun(T)(T t) {
        t.foobar(2, "quux");
    }

    auto m = mock;
    m.expect!"foobar"(3, "quux");
    fun(m);
    assertExceptionMsg(m.verify,
                       "    source/unit_threaded/mock.d:123 - foobar was called with unexpected Tuple!(int, string)(2, \"quux\")\n"
                       "    source/unit_threaded/mock.d:123 -           instead of the expected Tuple!(int, string)(3, \"quux\")");

}
