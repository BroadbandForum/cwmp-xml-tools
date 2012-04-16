# klaus.wich@nsn.com
# Display structure as XML
package nsn;

$gInd = 2;
$gIndTab = 4;


@ids = (0,0,0,0,0,0,0,0,0,0,0,0,0);
$MAXID = 12;
my %DataTypesTable;

sub indprint
{
	printf("% ${_[0]}s%s\n", "",$_[1]);
}


sub resetid
{
	my ($lev) = @_;
	for ($i= $lev+1; $i < $MAXID; $i++)
	{
		@ids[$i] = 0;
	}
}


sub nsn_node
{
	my ($node, $ind) = @_;
	
	if ($ind == 0)
	{
		foreach my $dtype (@{$node->{dataTypes}})
		{
			$type = ($dtype->{base} ne "") ? $dtype->{base} : $dtype->{prim};
			$tsize = 0;
			$syn = $dtype->{syntax};
			foreach my $size (@{$syn->{sizes}})
			{
				$size->{maxLength} and $tsize = $size->{maxLength};
			}
			if ($DataTypesTable{$type})
			{
				$tsize == 0 and $tsize = $DataTypesTable{$type}{size};
				$type = $DataTypesTable{$type}{type};
			}
			$DataTypesTable{$dtype->{name}}{type}=$type;
			$tsize > 0 and $DataTypesTable{$dtype->{name}}{size}=$tsize;
		}
	}
	
	#process nodes
	if ($ind > $gInd)
	{
		$ind = ($ind - $gInd);
		$i = $ind * $gIndTab;
		print "\n";
		@ids[$ind] += 1;
		if ($node->{type} ne "object")
		{
			indprint($i,"<!--PARAM: $node->{path}-->");
			indprint($i, "<$node->{name}");
			$des = $node->{description};
			$des =~ s/[\n\r\t<>]+//g;
			$des =~ s/["]+/ /g;
			indprint($i, "   description=\"$des\"");
			$type = $node->{type};
			$tbase = "node";
			if ($node->{syntax})
			{
				$syntax = $node->{syntax};
				if ($syntax->{ref})
				{
					$type = $syntax->{ref};
					$tbase = "syn-ref";
				}
				elsif ($syntax->{base})
				{
					$type = $syntax->{base};
					$tbase = "syn-base";
				}
			}
			#get length if defined
			$tsize="";
			if ($node->{syntax}) 
			{
				if ($node->{syntax}->{sizes})
				{
					foreach my $size (@{$node->{syntax}->{sizes}})
					{
						$size->{maxLength} and $tsize=sprintf("(%d)",$size->{maxLength});
					}
				}
			}
			# check if derived type
			if ($DataTypesTable{$type} ne "")
			{
				$otype = $type;
				$tsize eq "" and $tsize = $DataTypesTable{$type}{size};
				$type = $DataTypesTable{$type}{type};
			}
			indprint($i, "   type=\"$type\"");
			indprint($i, "   typeLength=\"$tsize\"");
			
			$rw = ($node->{access} eq "readWrite") ? "Write" : "Readonly";
			indprint($i, "   access=\"$rw\"");
			$def = ($node->{default} ne "") ? $node->{default} : "-";
			if ($def != "-")
			{
				indprint($i, "   default=\"$def\"");
			}
			indprint($i, "   version=\"$node->{majorVersion}.$node->{minorVersion}\"");
			indprint($i, "/>");
		}
		else
		{
			indprint($i,"<!--NODE: $node->{path}-->");
			$name = $node->{name};
			$islist = $name =~ /.+{i}/ ? " list=1>" : ">";
			$name =~ s /\..*//g;
			indprint($i, "<$name$islist");
		}
	}
}


sub nsn_init
{
	@ids = (0,0,0,0,0,0,0,0,0,0,0,0,0);  
	print "<?xml version=\"1.0\"?>\n<Model>\n";
}


sub nsn_postpar
{
	my ($node, $ind) = @_;
	if ($ind > $gInd)
	{
		$ind = ($ind - $gInd-1);
		$i = $ind * $gIndTab;
	}
}


sub nsn_post
{
	my ($node, $ind) = @_;
	if ($ind > $gInd)
	{
		$ind = ($ind - $gInd);
		$i = $ind * $gIndTab;
		if ($node->{type} eq "object")
		{
			$name = $node->{name};
			$name =~ s /\..*//g;
			indprint($i, "</$name>");
			indprint($i, "<!--NODE END: $node->{path}-->");
			resetid($ind);
		}
	}
}


sub nsn_end
{
	print "</Model>"
}


1;