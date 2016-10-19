enum Ensure
{
    Absent
    Present
}

class DockerImage {
    [string]$repository
    [string]$tag
    [string]$imageID
    [string]$size
    [datetime]$creationdate
    [string]$digest
    $TimeSinceCreation
    DockerImage( [string]$imageID,    [string]$repository,   [string]$tag,    [string]$digest,  [datetime]$creationDate,[string]$size){
        $this.repository = $repository
        $this.tag = $tag
        $this.imageID = $imageID
        $this.size = $size   
        $this.creationdate = $creationDate
        $this.digest = $digest
        $this.TimeSinceCreation = (get-date) - $this.creationdate
    }
    Pull(){
        docker pull 
    }
}


[DscResource()]
class cDockerImage
{
    
    [DscProperty(Key)]
    [string]$name
    
    [DscProperty()]    
    [Ensure] $ensure

    [DscProperty()]
    [string]$tag

    [DscProperty(NotConfigurable)]
    [string] $imageID

    [DscProperty(NotConfigurable)]
    [ValidateSet()]
    [string] $Size
    
    # Sets the desired state of the resource.
    [void] Set()
    {
        if(!$this.tag){$this.tag = 'latest'}
        docker pull "$($this.name):$($this.tag)" | out-null
    }        
    
    # Tests if the resource is in the desired state.
    [bool] Test()
    {        
        if(!$this.tag){$this.tag = 'latest'}
        docker images "$($this.name):$($this.tag)"
        return $true
    }    
    # Gets the resource's current state.
    [cDockerImage] Get()
    {        
        # NotConfigurable properties are set in the Get method.
        $this.P3 = something
        # Return this instance or construct a new instance.
        return $this 
    }    
}

Function getCurrentImages {
    [cmdletbinding()]
    Param(
        [string]$image = "microsoft/nanoserver",
        [string]$tag = 'latest',
        [validateset('local','remote','pull')]
        [string]$commandArgument = 'local'
        )
    switch($commandArgument){
        'local' {$f = 'images'}
        'remote' {$f = 'search'}
        'pull' {$f = 'pull'}
    }
    write-verbose "docker $f '$($image):$($tag)'"
    docker $f "$($image):$($tag)" --format "{{.ID}}:{{.Repository}}:{{.Tag}}:{{.Digest}}:{{.CreatedAt}}:{{.Size}}" | 
        convertfrom-string -TemplateContent "{ImageInfo:*{ID:e14bc0ecea12}:{Repository:microsoft/nanoserver}:{Tag:latest}:{Digest:<none>}:{CreatedDate:2016-09-22 05:39:30 -0400 EDT}:{Size:-1 B}}" |
        Select -ExpandProperty ImageInfo |
        foreach-object {            
            $creationDate = $_.CreationDate | 
                convertfrom-string -TemplateContent "{Date:*{{Year:2016}-{Month:09}-{Day:22} {Hour:05}:{Minute:39}:{Second:30} -{TimeZone:0400} {TimeZoneLabel:EDT}}}" |
                Select -ExpandProperty Date | select -ExpandProperty Anonymous_2 |
                foreach-object {get-date "$($_.Month)/$($_.Day)/$($_.Year) $($_.hour):$($_.minute):$($_.second)"}
            [DockerImage]::new($_.ID,$_.Repository,$_.tag,$_.digeest,$creationDate,$_.Size)
        }
}