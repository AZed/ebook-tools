package EBook::AttributeHandlers;
use Attribute::Handlers;

sub UNIVERSAL::HandlerTest :ATTR(CODE)
{
    my ($pkg, $sym, $referent, $attr, $data) = @_;

    print {*STDERR} (
        "DEBUG:",
        " package=",$pkg,
        " symbol=",*{$sym}{PACKAGE},"::",*{$sym}{NAME},
        " referent=",$referent,
        " attr=",$attr,
        " data=",join(" ",@$data),
        "\n"
        );
    return;
}

1;
