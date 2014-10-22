package foo;
 
sub foo_node
{
    my ($node) = @_;
    print "$node->{path}\n";
}

1;
